import SwiftUI

// MARK: - Gateway Dashboard Models

/// System-wide dashboard snapshot from gateway health + status APIs
///
/// API response structures (verified 2026-03-10):
///
/// health: { ok, durationMs, sessions: { count, recent: [{ key, age }] }, agents: [...] }
/// status: { sessions: { byAgent: [{ agentId, count, recent: [{ key, model, inputTokens, ... }] }] } }
struct GatewaySnapshot {
    let fetchedAt: Date
    let activeSessionCount: Int
    let currentModel: String
    let isHealthy: Bool
    let uptimeMs: Int

    var healthColor: Color {
        isHealthy ? DS.Semantic.success : DS.Semantic.warning
    }

    /// Compact summary: "3会话 · grok-4"
    var summaryText: String {
        let shortModel = String(currentModel.prefix(10))
        return "\(activeSessionCount)会话 \u{00b7} \(shortModel)"
    }

    /// Parse from health + status API responses
    static func parse(health: [String: Any]?, status: [String: Any]?) -> GatewaySnapshot? {
        // Need at least one data source
        guard health != nil || status != nil else { return nil }

        // Session count: health.sessions.count (top-level)
        let sessionCount: Int
        if let sessions = health?["sessions"] as? [String: Any],
           let count = sessions["count"] as? Int {
            sessionCount = count
        } else if let sessions = status?["sessions"] as? [String: Any],
                  let byAgent = sessions["byAgent"] as? [[String: Any]],
                  let first = byAgent.first,
                  let count = first["count"] as? Int {
            sessionCount = count
        } else {
            sessionCount = 0
        }

        // Current model: status.sessions.byAgent[0].recent[0].model
        var model = "?"
        if let sessions = status?["sessions"] as? [String: Any],
           let byAgent = sessions["byAgent"] as? [[String: Any]],
           let firstAgent = byAgent.first,
           let recent = firstAgent["recent"] as? [[String: Any]],
           let firstSession = recent.first,
           let m = firstSession["model"] as? String {
            model = m
        }

        // Health check: health.ok (top-level)
        let isOK = health?["ok"] as? Bool ?? false

        // Uptime: health.durationMs (top-level)
        let uptime = health?["durationMs"] as? Int ?? 0

        return GatewaySnapshot(
            fetchedAt: Date(),
            activeSessionCount: sessionCount,
            currentModel: model,
            isHealthy: isOK,
            uptimeMs: uptime
        )
    }
}

/// Per-session detail from gateway sessions.list / status API
///
/// Session fields (from status.sessions.byAgent[*].recent[*]):
///   key, model, inputTokens, outputTokens, cacheRead, cacheWrite,
///   contextTokens, percentUsed, displayName, updatedAt, sessionId
struct SessionDetail {
    let sessionKey: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let cacheWrite: Int
    let contextTokens: Int
    let percentUsed: Double?
    let displayName: String?
    let updatedAt: Date?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheRead + cacheWrite
    }

    /// Parse from a session entry in sessions.list or status API
    static func parse(from dict: [String: Any]) -> SessionDetail? {
        guard let key = dict["key"] as? String ?? dict["sessionKey"] as? String else {
            return nil
        }

        let model = dict["model"] as? String ?? "?"
        let input = dict["inputTokens"] as? Int ?? 0
        let output = dict["outputTokens"] as? Int ?? 0
        let cacheR = dict["cacheRead"] as? Int ?? 0
        let cacheW = dict["cacheWrite"] as? Int ?? 0
        let ctx = dict["contextTokens"] as? Int ?? 0

        // percentUsed may be null in gateway response
        var pct: Double? = nil
        if let p = dict["percentUsed"] as? Double {
            pct = p
        } else if ctx > 0 {
            let total = input + output + cacheR + cacheW
            pct = total > 0 ? Double(total) / Double(ctx) : nil
        }

        let displayName = dict["displayName"] as? String

        var updatedAt: Date? = nil
        if let ts = dict["updatedAt"] as? Double {
            updatedAt = Date(timeIntervalSince1970: ts / 1000.0)
        }

        return SessionDetail(
            sessionKey: key,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheRead: cacheR,
            cacheWrite: cacheW,
            contextTokens: ctx,
            percentUsed: pct,
            displayName: displayName,
            updatedAt: updatedAt
        )
    }
}
