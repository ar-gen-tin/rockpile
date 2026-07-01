import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "GatewaySessionRouter")

/// Routes Gateway push events into virtual crawfish (小龙虾) sessions.
///
/// When the Gateway broadcasts a session-level event (tool call, LLM output, etc.),
/// this router creates or updates a `SessionData` with `creatureType == .crawfish`
/// so it appears as a crawfish in the pond.
///
/// Also periodically syncs from `GatewayDashboard.sessionDetails` to update
/// remote token trackers.
@MainActor
@Observable
final class GatewaySessionRouter {
    static let shared = GatewaySessionRouter()

    private var syncTimer: Timer?
    private static let syncInterval: TimeInterval = 60

    private init() {
        startPeriodicSync()
    }

    // MARK: - Event Routing

    /// Route a Gateway push event into StateMachine as a crawfish session.
    /// Called from `GatewayClient.routeRemoteActivity`.
    func routeEvent(_ json: [String: Any], event: String) {
        guard let payload = json["payload"] as? [String: Any] else { return }

        // Extract session key
        let sessionKey = payload["sessionKey"] as? String
            ?? payload["key"] as? String
            ?? payload["session"] as? String

        guard let key = sessionKey else { return }

        // Map Gateway event to HookEvent equivalent
        let hookEvent = mapToHookEvent(gatewayEvent: event, sessionKey: key, payload: payload)
        guard let hookEvent else { return }

        // Route through StateMachine with gateway source → crawfish
        StateMachine.shared.handleEvent(hookEvent, source: .gateway)

        // Also notify RemoteActivityTracker for the badge UI
        RemoteActivityTracker.shared.recordActivity(sessionKey: key, eventType: event)
    }

    // MARK: - Periodic Sync

    /// Sync remote token data from GatewayDashboard into remote tracker.
    func syncFromDashboard() {
        let dashboard = GatewayDashboard.shared
        let sessionStore = StateMachine.shared.sessionStore

        // Update remote token tracker from dashboard session details
        for (_, detail) in dashboard.sessionDetails {
            if detail.inputTokens > 0 || detail.outputTokens > 0 {
                sessionStore.remoteTokenTracker.recordRemoteUsage(
                    inputTokens: detail.inputTokens,
                    outputTokens: detail.outputTokens,
                    cacheReadTokens: detail.cacheRead,
                    cacheWriteTokens: detail.cacheWrite
                )
            }
        }
    }

    /// Remove stale gateway sessions that are no longer in the snapshot.
    func cleanupStaleSessions() {
        let sessionStore = StateMachine.shared.sessionStore
        let gatewayKeys = Set(GatewayClient.shared.sessionKeys)

        // Only clean sessions that came from gateway and are no longer tracked
        let remoteSessions = sessionStore.remoteSessions
        for session in remoteSessions {
            // Gateway sessions have session keys as IDs — if key disappeared, remove
            if !gatewayKeys.isEmpty && !gatewayKeys.contains(session.id) {
                // Only remove if the session has been idle for a while
                let age = Date().timeIntervalSince(session.lastEventTime)
                if age > 120 { // 2 minutes grace period
                    sessionStore.removeSession(id: session.id)
                    logger.info("Removed stale gateway session: \(session.id.prefix(8), privacy: .public)")
                }
            }
        }
    }

    // MARK: - Private

    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Refresh dashboard data, then sync + cleanup
                await GatewayDashboard.shared.refreshIfNeeded()
                self?.syncFromDashboard()
                self?.cleanupStaleSessions()
            }
        }
    }

    /// Map a Gateway event name to a synthetic HookEvent for StateMachine.
    private func mapToHookEvent(gatewayEvent: String, sessionKey: String, payload: [String: Any]) -> HookEvent? {
        // Common fields
        let status = payload["status"] as? String ?? "idle"
        let tool = payload["tool"] as? String

        // Map Gateway event names to HookEvent event names
        let eventName: String
        switch gatewayEvent {
        case "session.start", "session.created":
            eventName = "SessionStart"
        case "session.end", "session.closed":
            eventName = "SessionEnd"
        case "llm.input", "llm.request":
            eventName = "LLMInput"
        case "llm.output", "llm.response":
            eventName = "LLMOutput"
        case "tool.call", "tool.invoked":
            eventName = "ToolCall"
        case "tool.result", "tool.completed":
            eventName = "ToolResult"
        case "agent.start":
            eventName = "AgentStart"
        case "agent.end":
            eventName = "AgentEnd"
        case "compaction":
            eventName = "Compaction"
        default:
            // Unknown event — still track as activity but don't create a hook event
            return nil
        }

        return HookEvent(sessionId: sessionKey, event: eventName, status: status, tool: tool)
    }
}
