import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "StateMachine")

@MainActor
@Observable
final class StateMachine {
    static let shared = StateMachine()

    let sessionStore = SessionStore()
    private var emotionDecayTimer: Timer?

    /// 最近错误 — 在 ExpandedPanelView 显示 toast
    private(set) var lastError: String?
    private var errorDismissTask: Task<Void, Never>?

    /// 报告用户可见错误（8 秒后自动消失）
    func reportError(_ message: String) {
        lastError = message
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.lastError = nil
        }
    }

    private init() {
        startEmotionDecay()
    }

    func handleEvent(_ event: HookEvent, source: EventSource = .tcpSocket) {
        guard !event.sessionId.isEmpty else {
            logger.warning("忽略空 sessionId 事件: \(event.event, privacy: .public)")
            return
        }
        let creatureType = source.creatureType
        let cwd = event.cwd ?? ""

        switch event.event {
        case "SessionStart":
            sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)

        case "SessionEnd":
            // Notify before removing
            if let session = sessionStore.session(for: event.sessionId) {
                NotificationManager.shared.notifySessionComplete(session: session)
            }
            NotificationManager.shared.cleanupSession(event.sessionId)
            sessionStore.removeSession(id: event.sessionId)

        case "MessageReceived":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.thinking)
            session.addActivity(ActivityItem(
                timestamp: Date(),
                type: .message,
                detail: event.userPrompt ?? "新消息"
            ))
            // Analyze emotion asynchronously
            if let prompt = event.userPrompt, !prompt.isEmpty {
                analyzeEmotion(prompt, for: session)
            }

        case "LLMInput":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.thinking)
            session.addActivity(ActivityItem(
                timestamp: Date(),
                type: .thinking,
                detail: "思考中..."
            ))
            // Analyze emotion from prompt if available
            if let prompt = event.userPrompt, !prompt.isEmpty {
                analyzeEmotion(prompt, for: session)
            }

        case "LLMOutput":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.working)
            NotificationManager.shared.notifyStateChange(sessionId: event.sessionId, creatureType: creatureType, newTask: .working)
            recordTokenUsage(event, for: session)

        case "ToolCall":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.working)
            session.addActivity(ActivityItem(
                timestamp: Date(),
                type: .toolCall,
                detail: event.tool ?? "Tool"
            ))

        case "ToolResult":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            if event.status == "error" || event.error != nil {
                session.updateTask(.error)
                NotificationManager.shared.notifyStateChange(sessionId: event.sessionId, creatureType: creatureType, newTask: .error)
                session.addActivity(ActivityItem(
                    timestamp: Date(),
                    type: .error,
                    detail: event.error ?? "工具出错"
                ))
                // Auto-recover from error after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if session.state.task == .error {
                        session.updateTask(.working)
                    }
                }
            } else {
                session.updateTask(.working)
                session.addActivity(ActivityItem(
                    timestamp: Date(),
                    type: .toolResult,
                    detail: "\(event.tool ?? "工具") 完成"
                ))
            }
            recordTokenUsage(event, for: session)
            // Sync conversation after tool results
            syncConversation(event, session: session)
            // Cancel any pending permission for this tool (user approved in terminal)
            if let toolUseId = event.toolUseId {
                PermissionHandler.shared.cancelIfPending(toolUseId)
            }

        case "AgentStart":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.working)

        case "AgentEnd":
            if let session = sessionStore.session(for: event.sessionId) {
                session.updateTask(.idle)
                session.addActivity(ActivityItem(
                    timestamp: Date(),
                    type: .completion,
                    detail: "完成"
                ))
                // Sync conversation on completion
                syncConversation(event, session: session)
            }

        case "SubagentSpawned":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.working)

        case "SubagentEnded":
            if let session = sessionStore.session(for: event.sessionId) {
                session.updateTask(.idle)
            }

        case "Compaction":
            let session = sessionStore.getOrCreateSession(id: event.sessionId, cwd: cwd, creatureType: creatureType)
            session.updateTask(.compacting)

        case "PermissionRequest":
            // Route to PermissionHandler
            if let toolUseId = event.toolUseId, !toolUseId.isEmpty {
                PermissionHandler.shared.addRequest(
                    toolUseId: toolUseId,
                    toolName: event.tool ?? "unknown",
                    toolInput: event.toolInput,
                    sessionId: event.sessionId
                )
                // Auto-expand notch to show permission banner
                PanelManager.shared.expand()
            }

        default:
            logger.info("Unknown event: \(event.event, privacy: .public)")
        }
    }

    private func recordTokenUsage(_ event: HookEvent, for session: SessionData) {
        // Only record if event contains usage data
        guard event.inputTokens != nil || event.outputTokens != nil || event.dailyTokensUsed != nil || event.rateLimited == true else {
            return
        }
        session.tokenTracker.recordUsage(from: event, sessionId: session.id)
        // 同步到全局 tracker，驱动常驻 O₂ 条
        sessionStore.globalTokenTracker.recordUsage(from: event, sessionId: session.id)
        // 同步到对应的 per-creature tracker
        switch session.creatureType {
        case .hermitCrab:
            sessionStore.localTokenTracker.recordUsage(from: event, sessionId: session.id)
        case .crawfish:
            sessionStore.remoteTokenTracker.recordUsage(from: event, sessionId: session.id)
        }

        // Check O₂ thresholds for notifications
        let o2Pct = Double(session.tokenTracker.oxygenPercent) / 100.0
        NotificationManager.shared.checkO2Thresholds(creatureType: session.creatureType, oxygenPercent: o2Pct)

        if session.tokenTracker.isDead {
            logger.warning("O₂ depleted! Token quota exhausted.")
        } else if session.tokenTracker.isLowOxygen {
            logger.info("O₂ low: \(session.tokenTracker.oxygenPercent)%")
        }
    }

    private func analyzeEmotion(_ prompt: String, for session: SessionData) {
        session.emotionTask?.cancel()
        session.emotionTask = Task {
            let (emotion, intensity) = await EmotionAnalyzer.shared.analyze(prompt)
            guard !Task.isCancelled else { return }
            logger.info("Emotion: \(emotion.rawValue, privacy: .public) @ \(intensity)")
            session.emotionState.recordEmotion(emotion, intensity: intensity)
        }
    }

    private func syncConversation(_ event: HookEvent, session: SessionData) {
        let sessionId = event.sessionId
        let cwd = session.cwd.isEmpty ? (event.userPrompt ?? "") : session.cwd
        guard !cwd.isEmpty else { return }
        Task {
            await ConversationParser.shared.syncSession(sessionId: sessionId, cwd: cwd)
        }
    }

    private func startEmotionDecay() {
        emotionDecayTimer = Timer.scheduledTimer(withTimeInterval: RC.Emotion.decayInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sessionStore.decayAllEmotions()
            }
        }
    }
}
