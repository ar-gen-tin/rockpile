import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "RemoteActivity")

/// 远程会话活动追踪器 — 统计 Gateway 推送的远程事件，驱动通知 UI
///
/// 两阶段显示：
/// 1. 折叠态 → headerRow 左侧显示 "📱 +N" 指示器（持久，直到用户展开）
/// 2. 展开态 → PondView 小龙虾弹出 "📱 +N" 气泡（4s 后自动消失）
///
/// 与 StateMachine 的区别：
/// - StateMachine 处理本地 HookEvent（插件 → Socket → StateMachine）
/// - RemoteActivityTracker 处理 Gateway 推送事件（远程 Telegram 等）
@MainActor
@Observable
final class RemoteActivityTracker {
    static let shared = RemoteActivityTracker()

    // MARK: - Header 指示器状态（折叠态左侧 📱 +N）

    /// 待处理的远程活动计数 — 驱动 header 指示器
    private(set) var pendingCount: Int = 0

    /// 最近一次活动的会话 key
    private(set) var lastSessionKey: String?

    // MARK: - 气泡状态（展开态小龙虾 📱 +N 气泡）

    /// 气泡正在显示
    private(set) var isBubbleShowing: Bool = false

    /// 气泡触发计数器 — 递增驱动 pop 动画
    private(set) var bubbleTrigger: Int = 0

    /// 气泡显示的计数值（快照，展开时冻结）
    private(set) var bubbleCount: Int = 0

    // MARK: - Private

    private var dismissTimer: Timer?
    private static let bubbleDuration: TimeInterval = 4.0
    private static let debounceWindow: TimeInterval = 0.5
    private var lastEventTimestamp: Date = .distantPast
    private var lastEventSessionKey: String?

    private init() {}

    // MARK: - 记录远程活动（Gateway 推送事件调用）

    func recordActivity(sessionKey: String, eventType: String) {
        let now = Date()

        // 防抖：同一会话 0.5s 内的连续事件合并
        if sessionKey == lastEventSessionKey,
           now.timeIntervalSince(lastEventTimestamp) < Self.debounceWindow {
            lastEventTimestamp = now
            return
        }

        lastEventTimestamp = now
        lastEventSessionKey = sessionKey
        pendingCount += 1
        lastSessionKey = sessionKey

        logger.info("Remote activity: +\(self.pendingCount) from \(sessionKey.prefix(30), privacy: .public) (\(eventType, privacy: .public))")
        EventLogger.shared.log("📱 远程活动: +\(pendingCount) | \(sessionKey.prefix(30)) | \(eventType)")
    }

    // MARK: - 展开面板时消费通知 → 触发气泡

    /// PondView onAppear 时调用 — 将 header 指示器转为小龙虾气泡
    func consumeForBubble() {
        guard pendingCount > 0 else { return }

        // 快照当前计数给气泡显示
        bubbleCount = pendingCount
        isBubbleShowing = true
        bubbleTrigger += 1

        EventLogger.shared.log("📱 气泡弹出: +\(bubbleCount)")

        // 4s 后自动消失
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: Self.bubbleDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissBubble()
            }
        }
    }

    // MARK: - Private

    private func dismissBubble() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        isBubbleShowing = false

        // fade-out 动画完成后清零
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pendingCount = 0
            self?.bubbleCount = 0
            self?.lastSessionKey = nil
            self?.lastEventSessionKey = nil
        }
    }
}
