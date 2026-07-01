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

    // MARK: - Event Dispatch (lil-agents 风格: 路由 + 独立 handler)

    func handleEvent(_ event: HookEvent, source: EventSource = .tcpSocket) {
        guard !event.sessionId.isEmpty else {
            logger.warning("忽略空 sessionId 事件: \(event.event, privacy: .public)")
            return
        }

        let ctx = EventContext(event: event, source: source)

        switch event.event {
        case "SessionStart":    handleSessionStart(ctx)
        case "SessionEnd":      handleSessionEnd(ctx)
        case "MessageReceived": handleMessageReceived(ctx)
        case "LLMInput":        handleLLMInput(ctx)
        case "LLMOutput":       handleLLMOutput(ctx)
        case "ToolCall":        handleToolCall(ctx)
        case "ToolResult":      handleToolResult(ctx)
        case "AgentStart":      handleAgentStart(ctx)
        case "AgentEnd":        handleAgentEnd(ctx)
        case "SubagentSpawned": handleSubagentSpawned(ctx)
        case "SubagentEnded":   handleSubagentEnded(ctx)
        case "Compaction":      handleCompaction(ctx)
        case "PermissionRequest": handlePermissionRequest(ctx)
        default:
            logger.info("Unknown event: \(event.event, privacy: .public)")
        }
    }

    // MARK: - Event Context (消除重复参数传递)

    /// 预解析的事件上下文 — 每个 handler 共享，避免重复解构
    private struct EventContext {
        let event: HookEvent
        let source: EventSource
        var creatureType: CreatureType { source.creatureType }
        var cwd: String { event.cwd ?? "" }
        var sessionId: String { event.sessionId }
    }

    /// 确保会话存在并返回 — 统一入口，消除 12 处重复 getOrCreateSession 调用
    private func ensureSession(_ ctx: EventContext) -> SessionData {
        sessionStore.getOrCreateSession(id: ctx.sessionId, cwd: ctx.cwd, creatureType: ctx.creatureType)
    }

    // MARK: - Event Handlers

    private func handleSessionStart(_ ctx: EventContext) {
        _ = ensureSession(ctx)
    }

    private func handleSessionEnd(_ ctx: EventContext) {
        if let session = sessionStore.session(for: ctx.sessionId) {
            NotificationManager.shared.notifySessionComplete(session: session)
        }
        NotificationManager.shared.cleanupSession(ctx.sessionId)
        sessionStore.removeSession(id: ctx.sessionId)
    }

    private func handleMessageReceived(_ ctx: EventContext) {
        let session = ensureSession(ctx)
        session.updateTask(.thinking)
        session.addActivity(ActivityItem(
            timestamp: Date(),
            type: .message,
            detail: ctx.event.userPrompt ?? "新消息"
        ))
        analyzeEmotionIfNeeded(ctx.event, for: session)
    }

    private func handleLLMInput(_ ctx: EventContext) {
        let session = ensureSession(ctx)
        session.updateTask(.thinking)
        session.addActivity(ActivityItem(
            timestamp: Date(),
            type: .thinking,
            detail: "思考中..."
        ))
        analyzeEmotionIfNeeded(ctx.event, for: session)
    }

    private func handleLLMOutput(_ ctx: EventContext) {
        let session = ensureSession(ctx)
        session.updateTask(.working)
        NotificationManager.shared.notifyStateChange(
            sessionId: ctx.sessionId, creatureType: ctx.creatureType, newTask: .working
        )
        recordTokenUsage(ctx.event, for: session)
    }

    private func handleToolCall(_ ctx: EventContext) {
        let session = ensureSession(ctx)
        session.updateTask(.working)
        session.addActivity(ActivityItem(
            timestamp: Date(),
            type: .toolCall,
            detail: ctx.event.tool ?? "Tool"
        ))
    }

    private func handleToolResult(_ ctx: EventContext) {
        let session = ensureSession(ctx)
        let isError = ctx.event.status == "error" || ctx.event.error != nil

        if isError {
            session.updateTask(.error)
            NotificationManager.shared.notifyStateChange(
                sessionId: ctx.sessionId, creatureType: ctx.creatureType, newTask: .error
            )
            session.addActivity(ActivityItem(
                timestamp: Date(),
                type: .error,
                detail: ctx.event.error ?? "工具出错"
            ))
            // Auto-recover from error after 3 seconds
            Task { [weak session] in
                try? await Task.sleep(for: .seconds(3))
                if session?.state.task == .error {
                    session?.updateTask(.working)
                }
            }
        } else {
            session.updateTask(.working)
            session.addActivity(ActivityItem(
                timestamp: Date(),
                type: .toolResult,
                detail: "\(ctx.event.tool ?? "工具") 完成"
            ))
        }

        recordTokenUsage(ctx.event, for: session)
        syncConversation(ctx.event, session: session)

        // Cancel any pending permission for this tool (user approved in terminal)
        if let toolUseId = ctx.event.toolUseId {
            PermissionHandler.shared.cancelIfPending(toolUseId)
        }
    }

    private func handleAgentStart(_ ctx: EventContext) {
        ensureSession(ctx).updateTask(.working)
    }

    private func handleAgentEnd(_ ctx: EventContext) {
        guard let session = sessionStore.session(for: ctx.sessionId) else { return }
        session.updateTask(.idle)
        session.addActivity(ActivityItem(
            timestamp: Date(),
            type: .completion,
            detail: "完成"
        ))
        syncConversation(ctx.event, session: session)
    }

    private func handleSubagentSpawned(_ ctx: EventContext) {
        ensureSession(ctx).updateTask(.working)
    }

    private func handleSubagentEnded(_ ctx: EventContext) {
        sessionStore.session(for: ctx.sessionId)?.updateTask(.idle)
    }

    private func handleCompaction(_ ctx: EventContext) {
        ensureSession(ctx).updateTask(.compacting)
    }

    private func handlePermissionRequest(_ ctx: EventContext) {
        guard let toolUseId = ctx.event.toolUseId, !toolUseId.isEmpty else { return }
        PermissionHandler.shared.addRequest(
            toolUseId: toolUseId,
            toolName: ctx.event.tool ?? "unknown",
            toolInput: ctx.event.toolInput,
            sessionId: ctx.sessionId
        )
        PanelManager.shared.expand()
    }

    // MARK: - Shared Helpers

    private func recordTokenUsage(_ event: HookEvent, for session: SessionData) {
        guard event.inputTokens != nil || event.outputTokens != nil
                || event.dailyTokensUsed != nil || event.rateLimited == true else {
            return
        }
        session.tokenTracker.recordUsage(from: event, sessionId: session.id)
        sessionStore.globalTokenTracker.recordUsage(from: event, sessionId: session.id)

        // Sync to per-creature tracker
        switch session.creatureType {
        case .hermitCrab:
            sessionStore.localTokenTracker.recordUsage(from: event, sessionId: session.id)
        case .crawfish:
            sessionStore.remoteTokenTracker.recordUsage(from: event, sessionId: session.id)
        }

        // Check O₂ thresholds
        let o2Pct = Double(session.tokenTracker.oxygenPercent) / 100.0
        NotificationManager.shared.checkO2Thresholds(creatureType: session.creatureType, oxygenPercent: o2Pct)

        if session.tokenTracker.isDead {
            logger.warning("O₂ depleted! Token quota exhausted.")
        } else if session.tokenTracker.isLowOxygen {
            logger.info("O₂ low: \(session.tokenTracker.oxygenPercent)%")
        }
    }

    /// Analyze emotion only when a non-empty prompt is available
    private func analyzeEmotionIfNeeded(_ event: HookEvent, for session: SessionData) {
        guard let prompt = event.userPrompt, !prompt.isEmpty else { return }
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
