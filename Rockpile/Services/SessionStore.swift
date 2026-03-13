import Foundation
import Observation

/// 会话存储 — 管理所有活跃的 Rockpile Agent 会话
///
/// 职责：
/// - 维护 `sessions` 字典（session_id → SessionData）
/// - 为每个会话分配递增编号和随机 X 位置（避免小龙虾重叠）
/// - 每 15 秒扫描清理过期会话（sleeping 立即清理，idle 超 5 分钟清理）
/// - 会话结束时自动保存对话记录到 `SessionHistory`
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [String: SessionData] = [:]
    private(set) var selectedSessionId: String?
    private var sessionCounter = 0
    private var cleanupTimer: Timer?

    /// 全局 TokenTracker — 即使无活跃会话也保留最新 token 数据，驱动常驻 O₂ 条
    let globalTokenTracker = TokenTracker()

    /// Sessions idle/sleeping longer than this are automatically removed
    private static let sessionTimeout: TimeInterval = 300 // 5 分钟（进入休眠即超时）

    init() {
        localTokenTracker.creatureType = .crawfish
        remoteTokenTracker.creatureType = .crawfish
        startCleanupTimer()
    }

    // Note: No deinit needed — singleton (`shared`) is never deallocated.
    // Adding deinit would require `nonisolated(unsafe)` on cleanupTimer
    // due to Swift 6 MainActor isolation rules.

    var sortedSessions: [SessionData] {
        sessions.values.sorted { $0.sessionNumber < $1.sessionNumber }
    }

    var activeSessionCount: Int {
        sessions.count
    }

    var effectiveSession: SessionData? {
        if let selectedSessionId, let session = sessions[selectedSessionId] {
            return session
        }
        return sortedSessions.first
    }

    // MARK: - Per-Creature Queries

    /// All local sessions (hermit crab / Claude Code)
    var localSessions: [SessionData] {
        sessions.values.filter { $0.creatureType == .hermitCrab }
            .sorted { $0.sessionNumber < $1.sessionNumber }
    }

    /// All remote sessions (crawfish / Openclaw)
    var remoteSessions: [SessionData] {
        sessions.values.filter { $0.creatureType == .crawfish }
            .sorted { $0.sessionNumber < $1.sessionNumber }
    }

    /// Effective local session (first active hermit crab)
    var effectiveLocalSession: SessionData? {
        localSessions.first
    }

    /// Effective remote session (first active crawfish)
    var effectiveRemoteSession: SessionData? {
        remoteSessions.first
    }

    /// Dedicated token tracker for local sessions
    let localTokenTracker = TokenTracker()

    /// Dedicated token tracker for remote sessions
    let remoteTokenTracker = TokenTracker()

    @discardableResult
    func getOrCreateSession(id: String, cwd: String, creatureType: CreatureType = .crawfish) -> SessionData {
        if let existing = sessions[id] {
            return existing
        }
        sessionCounter += 1
        let existingPositions = sessions.values.map(\.spriteXPosition)
        let session = SessionData(
            sessionId: id,
            cwd: cwd,
            sessionNumber: sessionCounter,
            creatureType: creatureType,
            existingXPositions: existingPositions
        )
        sessions[id] = session
        EventLogger.shared.logSessionCreated(id: id, total: sessions.count)
        // Flush any queued commands now that a session is available
        CommandSender.shared.flushQueueIfNeeded()
        return session
    }

    func session(for id: String) -> SessionData? {
        sessions[id]
    }

    func removeSession(id: String) {
        // Log summary + save history before removing
        if let session = sessions[id], !session.activities.isEmpty {
            let toolCalls = session.activities.filter { $0.type == .toolCall }.count
            let startTime = session.activities.first?.timestamp ?? session.lastEventTime
            let duration = Date().timeIntervalSince(startTime)
            EventLogger.shared.logSessionSummary(
                id: id,
                duration: duration,
                activityCount: session.activities.count,
                toolCalls: toolCalls,
                totalTokens: session.tokenTracker.sessionTotalTokens
            )
            SessionHistory.shared.addRecord(from: session)
        }
        sessions[id]?.cleanup()
        sessions.removeValue(forKey: id)
        if selectedSessionId == id {
            selectedSessionId = nil
        }
        EventLogger.shared.logSessionRemoved(id: id, reason: "SessionEnd", remaining: sessions.count)
    }

    func selectSession(_ id: String?) {
        selectedSessionId = id
    }

    func decayAllEmotions() {
        for session in sessions.values {
            session.emotionState.decay()
            session.syncEmotion()
        }
    }

    // MARK: - Stale Session Cleanup

    private func startCleanupTimer() {
        // Check every 15 seconds for faster cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleSessions()
            }
        }
    }

    private func cleanupStaleSessions() {
        let now = Date()
        let staleIds = sessions.filter { (_, session) in
            let age = now.timeIntervalSince(session.lastEventTime)
            // Remove if: sleeping (already timed out) OR idle for > 5 min
            return session.state.task == .sleeping ||
                   (age > Self.sessionTimeout && session.state.task == .idle)
        }.map(\.key)

        guard !staleIds.isEmpty else { return }

        EventLogger.shared.logCleanup(removedCount: staleIds.count, ids: staleIds)

        for id in staleIds {
            removeSession(id: id)
        }
    }
}
