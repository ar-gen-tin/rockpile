import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "GatewayClient")

/// Rockpile Gateway WebSocket 客户端 — 双向通信核心
///
/// 连接流程：
///   1. WebSocket 连接 `ws://<host>:<port>`
///   2. 收到 `connect.challenge` (含 nonce)
///   3. 发送 `connect` 请求 (token auth)
///   4. 收到 `hello-ok` → 连接就绪
///
/// 使用 `chat.send` 方法发送指令给 Rockpile。
@MainActor
@Observable
final class GatewayClient {
    static let shared = GatewayClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case connected
    }

    private(set) var state: ConnectionState = .disconnected
    private(set) var connectionId: String?

    /// Available session keys from gateway snapshot
    private(set) var sessionKeys: [String] = []

    private var wsTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = RC.Gateway.maxReconnectDelay
    static let requestTimeout: TimeInterval = RC.Gateway.requestTimeout
    private var pendingRequests: [String: CheckedContinuation<GatewayResponse, Error>] = [:]
    private var intentionalDisconnect = false

    private init() {}

    // MARK: - Public API

    /// Connect to Rockpile gateway
    func connect() {
        guard state == .disconnected else { return }
        intentionalDisconnect = false
        performConnect()
    }

    /// Disconnect from gateway
    func disconnect() {
        intentionalDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        teardown()
    }

    /// Send a chat message to Rockpile
    func sendChat(message: String, sessionKey: String) async throws -> GatewayResponse {
        guard state == .connected else {
            throw GatewayError.notConnected
        }
        let id = UUID().uuidString
        let req: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": message,
                "deliver": true,
                "idempotencyKey": UUID().uuidString,
            ] as [String: Any],
        ]
        return try await sendRequest(id: id, payload: req)
    }

    /// Check if gateway is reachable (non-connecting health probe)
    var isConnected: Bool { state == .connected }

    // MARK: - Connection

    private func performConnect() {
        state = .connecting

        let host: String
        let port = AppSettings.gatewayPort

        switch AppSettings.setupRole {
        case .local, .host:
            host = "127.0.0.1"
        case .monitor:
            let remoteHost = AppSettings.rockpileHost
            guard !remoteHost.isEmpty else {
                logger.error("No rockpileHost configured for monitor mode")
                state = .disconnected
                return
            }
            host = remoteHost
        case .none:
            host = "127.0.0.1"
        }

        guard let url = URL(string: "ws://\(host):\(port)") else {
            logger.error("Invalid gateway URL")
            state = .disconnected
            return
        }

        logger.info("Connecting to gateway: \(url.absoluteString, privacy: .public)")

        // Reuse or create URLSession (avoid leak from creating new sessions each reconnect)
        if wsSession == nil {
            wsSession = URLSession(configuration: .default)
        }
        let task = wsSession!.webSocketTask(with: url)
        wsTask = task
        task.resume()

        logger.info("WS task resumed, starting receive loop")

        // Start receive loop (nonisolated to avoid MainActor blocking on ws.receive)
        Task.detached { [weak self] in
            await self?.receiveLoop(ws: task)
        }
    }

    private func teardown() {
        pingTimer?.invalidate()
        pingTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        connectionId = nil

        // Invalidate session on intentional disconnect to release resources
        if intentionalDisconnect {
            wsSession?.invalidateAndCancel()
            wsSession = nil
        }

        // Fail all pending requests
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: GatewayError.disconnected)
        }

        if state != .disconnected {
            state = .disconnected
            EventLogger.shared.logCommandResult(action: "gateway", result: "disconnected")
        }
    }

    // MARK: - Receive Loop

    private nonisolated func receiveLoop(ws: URLSessionWebSocketTask) async {
        while ws.state == .running {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await MainActor.run { [weak self] in self?.handleMessage(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await MainActor.run { [weak self] in self?.handleMessage(text) }
                    }
                @unknown default:
                    break
                }
            } catch {
                logger.warning("WS receive error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in self?.handleDisconnect() }
                return
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.warning("Malformed WS message")
            return
        }

        switch type {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            logger.info("Unknown frame type: \(type, privacy: .public)")
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? String else { return }
        logger.info("Event received: \(event, privacy: .public)")

        switch event {
        case "connect.challenge":
            guard let payload = json["payload"] as? [String: Any],
                  let nonce = payload["nonce"] as? String else {
                logger.error("Malformed connect.challenge")
                teardown()
                return
            }
            logger.info("Challenge nonce: \(nonce.prefix(8), privacy: .public)..., authenticating")
            state = .authenticating
            sendConnectAuth(nonce: nonce)

        default:
            // 🔔 诊断日志：记录所有 Gateway 推送事件，用于发现可用事件类型
            let payloadStr: String
            if let payload = json["payload"],
               let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                payloadStr = String(str.prefix(300))
            } else {
                payloadStr = "(no payload)"
            }
            EventLogger.shared.log("🔔 GW事件: \(event) | \(payloadStr)")

            // 路由到远程活动追踪器
            routeRemoteActivity(json, event: event)
        }
    }

    /// Route all Gateway push events to GatewaySessionRouter for crawfish session management.
    private func routeRemoteActivity(_ json: [String: Any], event: String) {
        GatewaySessionRouter.shared.routeEvent(json, event: event)
    }

    // MARK: - Authentication

    private func sendConnectAuth(nonce: String) {
        let token = resolveGatewayToken()
        guard !token.isEmpty else {
            logger.error("No gateway token available")
            teardown()
            return
        }

        let id = UUID().uuidString
        let connectReq: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "gateway-client",
                    "version": AppSettings.currentAppVersion,
                    "platform": "darwin",
                    "mode": "backend",
                ] as [String: Any],
                "caps": ["tool-events"] as [String],
                "role": "operator",
                "scopes": ["operator.admin"],
                "auth": [
                    "token": token,
                ] as [String: Any],
            ] as [String: Any],
        ]

        // Register pending request for hello-ok
        Task {
            do {
                let response = try await sendRequest(id: id, payload: connectReq)
                handleHelloOk(response)
            } catch {
                logger.error("Auth failed: \(error.localizedDescription)")
                teardown()
                scheduleReconnect()
            }
        }
    }

    private func handleHelloOk(_ response: GatewayResponse) {
        guard response.ok else {
            let msg = response.errorMessage ?? "unknown"
            logger.error("Auth rejected: \(msg, privacy: .public)")
            StateMachine.shared.reportError("Gateway 认证失败: \(msg)")
            teardown()
            scheduleReconnect()
            return
        }

        // Extract connectionId
        if let payload = response.payload,
           let server = payload["server"] as? [String: Any],
           let connId = server["connId"] as? String {
            connectionId = connId
        }

        // Extract session keys from snapshot
        // Path: snapshot.health.agents[*].sessions.recent[*].key
        if let payload = response.payload,
           let snapshot = payload["snapshot"] as? [String: Any] {
            var keys: [String] = []
            if let health = snapshot["health"] as? [String: Any],
               let agents = health["agents"] as? [[String: Any]] {
                for agent in agents {
                    if let sessions = agent["sessions"] as? [String: Any],
                       let recent = sessions["recent"] as? [[String: Any]] {
                        for sess in recent {
                            if let key = sess["key"] as? String {
                                keys.append(key)
                            }
                        }
                    }
                }
            }
            sessionKeys = keys
            if !keys.isEmpty {
                logger.info("Found \(keys.count) session(s) in snapshot: \(keys.first ?? "", privacy: .public)")
            }
        }

        state = .connected
        reconnectDelay = 1.0
        logger.info("Gateway connected (id: \(self.connectionId ?? "?", privacy: .public))")
        NotificationManager.shared.notifyConnectionChange(type: "Gateway", connected: true)

        let sessInfo = sessionKeys.isEmpty ? "无会话" : "\(sessionKeys.count)个会话"
        EventLogger.shared.logCommandResult(action: "gateway", result: "connected (\(sessInfo))")

        // Flush any queued commands now that we're connected
        CommandSender.shared.flushQueueIfNeeded()

        startPing()
    }

    /// Resolve gateway token: local reads from config file, remote uses AppSettings
    private func resolveGatewayToken() -> String {
        switch AppSettings.setupRole {
        case .local, .host:
            // Read from local ~/.rockpile/rockpile.json
            if let token = AppSettings.readLocalGatewayToken() {
                return token
            }
            // Fallback to manually configured token
            return AppSettings.gatewayToken
        case .monitor:
            return AppSettings.gatewayToken
        case .none:
            return AppSettings.readLocalGatewayToken() ?? AppSettings.gatewayToken
        }
    }

    // MARK: - Request/Response

    static let maxPendingRequests = RC.Gateway.maxPendingRequests

    private func sendRequest(id: String, payload: [String: Any]) async throws -> GatewayResponse {
        guard let ws = wsTask else { throw GatewayError.notConnected }
        guard pendingRequests.count < Self.maxPendingRequests else {
            throw GatewayError.tooManyRequests
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encodingError
        }

        // Send the message first
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ws.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Register pending request and start timeout
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GatewayResponse, Error>) in
            pendingRequests[id] = continuation

            // Timeout: fail the request if no response within limit
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.requestTimeout))
                if let cont = self?.pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: GatewayError.requestTimeout)
                }
            }
        }
        return response
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String,
              let continuation = pendingRequests.removeValue(forKey: id) else {
            return
        }

        let ok = json["ok"] as? Bool ?? false
        let error = json["error"] as? [String: Any]
        let errorMsg = error?["message"] as? String

        // Serialize payload back to Data for Sendable safety
        var payloadData: Data?
        if let payload = json["payload"] {
            payloadData = try? JSONSerialization.data(withJSONObject: payload)
        }

        let response = GatewayResponse(ok: ok, payloadData: payloadData, errorMessage: errorMsg)
        continuation.resume(returning: response)
    }

    // MARK: - Public API (Dashboard Methods)

    /// Call any gateway method by name. Returns the parsed response.
    func callMethod(_ method: String, params: [String: Any] = [:]) async throws -> GatewayResponse {
        guard state == .connected else { throw GatewayError.notConnected }

        let id = UUID().uuidString
        let req: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params,
        ]
        return try await sendRequest(id: id, payload: req)
    }

    /// Fetch gateway health (agents, channels, sessions summary)
    func fetchHealth() async throws -> GatewayResponse {
        try await callMethod("health")
    }

    /// Fetch system status (session details, heartbeat, channel summary)
    func fetchStatus() async throws -> GatewayResponse {
        try await callMethod("status")
    }

    /// Fetch all active sessions with full detail
    func fetchSessionsList() async throws -> GatewayResponse {
        try await callMethod("sessions.list")
    }

    // MARK: - Keepalive

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: RC.Gateway.pingInterval, repeats: true) { [weak self] _ in
            self?.wsTask?.sendPing { error in
                if let error {
                    logger.warning("Ping failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        teardown()
        NotificationManager.shared.notifyConnectionChange(type: "Gateway", connected: false)
        if !intentionalDisconnect {
            StateMachine.shared.reportError("Gateway 连接断开，正在重连…")
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !intentionalDisconnect else { return }

        let baseDelay = reconnectDelay
        // ±25% jitter 防雷群效应 (CodexBar pattern)
        let jitter = baseDelay * Double.random(in: -0.25...0.25)
        let delay = max(1.0, baseDelay + jitter)
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

        logger.info("Reconnecting in \(String(format: "%.1f", delay), privacy: .public)s...")
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performConnect()
            }
        }
    }
}

// MARK: - AgentDataProvider Conformance

extension GatewayClient: AgentDataProvider {
    var providerType: ProviderType { .gateway }
    var providerName: String { "GatewayClient" }
    var connectionState: ProviderConnectionState {
        switch state {
        case .disconnected:   return .disconnected
        case .connecting:     return .connecting
        case .authenticating: return .connecting
        case .connected:      return .connected
        }
    }
    var creatureType: CreatureType? { .crawfish }
    func connectProvider() { connect() }
    func disconnectProvider() { disconnect() }
}

// MARK: - Types

struct GatewayResponse: Sendable {
    let ok: Bool
    /// Raw payload JSON as Data (to avoid [String: Any] Sendable issues)
    let payloadData: Data?
    let errorMessage: String?

    /// Parse payload as dictionary (call on MainActor)
    var payload: [String: Any]? {
        guard let data = payloadData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

enum GatewayError: LocalizedError {
    case notConnected
    case disconnected
    case encodingError
    case authFailed(String)
    case requestTimeout
    case tooManyRequests

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Gateway 未连接"
        case .disconnected: return "连接已断开"
        case .encodingError: return "编码错误"
        case .authFailed(let msg): return "认证失败: \(msg)"
        case .requestTimeout: return "请求超时 (30s)"
        case .tooManyRequests: return "请求过多 (上限 \(RC.Gateway.maxPendingRequests))"
        }
    }
}
