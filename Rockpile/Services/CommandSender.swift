import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "CommandSender")

/// 反向通信客户端 — Rockpile → Rockpile Gateway
///
/// 通过 Gateway WebSocket 的 `chat.send` 方法发送指令。
/// - Gateway 连接就绪时直接发送
/// - 未连接时队列 1 条消息，TTL 30s
/// - UI 通过 `lastResult` 驱动状态反馈
@MainActor
@Observable
final class CommandSender {
    static let shared = CommandSender()

    enum SendResult: Equatable {
        case idle
        case sending
        case sent(method: String)
        case queued
        case noSession
        case error(String)
    }

    private(set) var lastResult: SendResult = .idle

    /// Queued command waiting for gateway connection (TTL 30s)
    private var queuedMessage: (message: String, sessionId: String?)?
    private var queueTimer: Timer?

    private init() {}

    // MARK: - Public API

    /// Send a chat message to Rockpile via Gateway WebSocket
    func sendChat(message: String, sessionId: String? = nil) {
        let gateway = GatewayClient.shared

        guard gateway.isConnected else {
            // Queue if not connected
            if queuedMessage == nil {
                queueCommand(message: message, sessionId: sessionId)
            } else {
                lastResult = .error(L10n.s("cmd.queued"))
            }
            return
        }

        // Resolve session key
        let sessionKey = resolveSessionKey(sessionId: sessionId)
        guard let sessionKey, !sessionKey.isEmpty else {
            lastResult = .noSession
            EventLogger.shared.logCommandResult(action: "chat", result: "no_session")
            return
        }

        lastResult = .sending

        Task {
            do {
                let response = try await gateway.sendChat(message: message, sessionKey: sessionKey)
                if response.ok {
                    lastResult = .sent(method: "gateway")
                    EventLogger.shared.logCommandSent(action: "chat", sessionId: sessionKey, method: "gateway")
                } else {
                    let errMsg = response.errorMessage ?? L10n.s("cmd.unknown")
                    lastResult = .error(errMsg)
                    EventLogger.shared.logCommandResult(action: "chat", result: "gateway_error: \(errMsg)")
                }
            } catch {
                lastResult = .error("\(L10n.s("cmd.failed")): \(error.localizedDescription)")
                EventLogger.shared.logCommandResult(action: "chat", result: "send_error: \(error.localizedDescription)")
            }
        }
    }

    /// Send interrupt signal (未实现 — Gateway 暂不支持)
    func sendInterrupt(sessionId: String? = nil) {
        lastResult = .error(L10n.s("cmd.emergencyWIP"))
    }

    /// Try to flush queued message (called when gateway connects)
    func flushQueueIfNeeded() {
        guard let queued = queuedMessage else { return }
        queuedMessage = nil
        queueTimer?.invalidate()
        queueTimer = nil
        logger.info("Flushing queued command")
        sendChat(message: queued.message, sessionId: queued.sessionId)
    }

    // MARK: - Private

    /// Resolve which gateway session key to send to.
    ///
    /// `chat.send` is a Gateway method — requires a gateway session key
    /// (format: `agent:main:telegram:...`), NOT a local plugin session ID.
    /// Priority: gateway session keys → nil (no session).
    private func resolveSessionKey(sessionId: String?) -> String? {
        let gatewayKeys = GatewayClient.shared.sessionKeys

        // If an explicit gateway key was provided, verify it exists
        if let sessionId, !sessionId.isEmpty,
           gatewayKeys.contains(sessionId) {
            return sessionId
        }

        // Use the first available gateway session key
        // (most recently active session from hello-ok snapshot)
        if let first = gatewayKeys.first {
            return first
        }

        return nil
    }

    private func queueCommand(message: String, sessionId: String?) {
        queuedMessage = (message: message, sessionId: sessionId)
        lastResult = .queued
        logger.info("Command queued (TTL 30s)")
        EventLogger.shared.logCommandResult(action: "chat", result: "queued")

        queueTimer?.invalidate()
        queueTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.queuedMessage = nil
                self?.queueTimer = nil
                self?.lastResult = .error(L10n.s("cmd.expired"))
                EventLogger.shared.logCommandResult(action: "chat", result: "queue_expired")
            }
        }
    }
}
