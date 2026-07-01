import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "GatewayDashboard")

/// Gateway 仪表板数据服务 — 缓存 + 按需拉取 dashboard 数据
///
/// 足迹视图打开时调用 `refreshIfNeeded()`，从 Gateway 拉取：
/// - `health` → 系统健康状态
/// - `status` → 会话详情 + 心跳配置
/// - `sessions.list` → 每个会话的 token 明细
///
/// 数据缓存 60 秒，避免重复请求。
@MainActor
@Observable
final class GatewayDashboard {
    static let shared = GatewayDashboard()

    /// System-wide snapshot (from health + status)
    private(set) var snapshot: GatewaySnapshot?

    /// Per-session detail keyed by session key
    private(set) var sessionDetails: [String: SessionDetail] = [:]

    /// Whether a fetch is in progress
    private(set) var isLoading: Bool = false

    /// Last fetch error (for debugging)
    private(set) var lastError: String?

    private var lastFetchTime: Date = .distantPast
    private static let cacheTTL: TimeInterval = 60

    private init() {}

    // MARK: - Public API

    /// Refresh dashboard data if cache is stale (> 60s) or empty.
    /// Called when the 足迹 view appears.
    func refreshIfNeeded() async {
        // Skip if cache is fresh
        guard Date().timeIntervalSince(lastFetchTime) > Self.cacheTTL else {
            return
        }

        // Skip if Gateway not connected
        guard GatewayClient.shared.state == .connected else {
            logger.info("Gateway not connected, skipping dashboard refresh")
            return
        }

        // Skip if already loading
        guard !isLoading else { return }

        isLoading = true
        lastError = nil

        do {
            // Fetch health + status + sessions in parallel
            async let healthResp = GatewayClient.shared.fetchHealth()
            async let statusResp = GatewayClient.shared.fetchStatus()
            async let sessionsResp = GatewayClient.shared.fetchSessionsList()

            let health = try await healthResp
            let status = try await statusResp
            let sessions = try await sessionsResp

            // Parse snapshot from health + status
            let healthDict = health.payload
            let statusDict = status.payload

            let snap = GatewaySnapshot.parse(health: healthDict, status: statusDict)
            snapshot = snap
            EventLogger.shared.log("📊 Dashboard: \(snap?.summaryText ?? "parse失败") | health=\(healthDict != nil) status=\(statusDict != nil)")

            // Parse session details from sessions.list + status
            parseSessionDetails(from: sessions, status: statusDict)

            lastFetchTime = Date()
            EventLogger.shared.log("📊 Dashboard刷新完成: \(self.sessionDetails.count)个会话详情")

        } catch {
            lastError = error.localizedDescription
            EventLogger.shared.log("❌ Dashboard刷新失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Force refresh regardless of cache TTL
    func forceRefresh() async {
        lastFetchTime = .distantPast
        await refreshIfNeeded()
    }

    /// Get detail for a specific session key (if cached)
    func detail(forSessionKey key: String) -> SessionDetail? {
        sessionDetails[key]
    }

    // MARK: - Private Parsing

    private func parseSessionDetails(from sessionsResp: GatewayResponse, status statusDict: [String: Any]?) {
        var details: [String: SessionDetail] = [:]

        // Parse from sessions.list response
        // sessions.list returns { sessions: { byAgent: [{ recent: [...] }] } }
        if let payload = sessionsResp.payload {
            if let sessions = payload["sessions"] as? [String: Any],
               let byAgent = sessions["byAgent"] as? [[String: Any]] {
                for agent in byAgent {
                    if let recent = agent["recent"] as? [[String: Any]] {
                        for dict in recent {
                            if let detail = SessionDetail.parse(from: dict) {
                                details[detail.sessionKey] = detail
                            }
                        }
                    }
                }
            }
        }

        // Enrich with status API data (has cacheRead/cacheWrite breakdown)
        // status returns { sessions: { byAgent: [{ recent: [...] }] } }
        if let sessions = statusDict?["sessions"] as? [String: Any],
           let byAgent = sessions["byAgent"] as? [[String: Any]] {
            for agent in byAgent {
                if let recent = agent["recent"] as? [[String: Any]] {
                    for dict in recent {
                        if let detail = SessionDetail.parse(from: dict) {
                            // Merge: status API often has more token detail
                            if details[detail.sessionKey] == nil || detail.inputTokens > 0 {
                                details[detail.sessionKey] = detail
                            }
                        }
                    }
                }
            }
        }

        sessionDetails = details
    }
}
