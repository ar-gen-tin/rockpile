import Foundation
import Observation

/// 生物互动协调器 — 控制寄居蟹和小龙虾的闲暇互动动画
///
/// **产品逻辑**:
/// - 两只生物都空闲/休眠且存活时，随机触发互动
/// - 小龙虾下沉到底部与寄居蟹会合
/// - 互动类型: 碰撞、玩耍、碰拳、依偎
/// - 互动完毕后各自回到原位
///
/// **架构**: `@MainActor @Observable` 单例，同 `RemoteActivityTracker.shared` 模式
/// 两个 SpriteView 各自观察 `phase` 来驱动位移动画
@MainActor
@Observable
final class InteractionCoordinator {
    static let shared = InteractionCoordinator()

    // MARK: - Types

    enum Phase: Equatable {
        case idle                          // 无互动
        case approaching(InteractionType)  // 双方向会合点移动
        case interacting(InteractionType)  // 播放互动动画
        case retreating                    // 返回原位
    }

    enum InteractionType: String, CaseIterable, Equatable {
        case bump      // 碰撞弹开
        case play      // 绕圈追逐
        case highFive  // 钳子碰拳 + 星星
        case nuzzle    // 并排摇摆
    }

    // MARK: - Observable State

    /// 当前互动阶段 — 两个 SpriteView 观察此值驱动动画
    private(set) var phase: Phase = .idle

    /// 会合点 X (归一化 0.0~1.0)
    private(set) var meetingX: CGFloat = 0.5

    /// 粒子特效触发计数器
    private(set) var fxTrigger: Int = 0

    // MARK: - Eligibility Gates (由 SpriteView 设置)

    /// 小龙虾是否可互动 (idle/sleeping + alive + not dragged)
    var crawfishCanInteract: Bool = false {
        didSet { checkAndScheduleIfReady() }
    }

    /// 寄居蟹是否可互动
    var crabCanInteract: Bool = false {
        didSet { checkAndScheduleIfReady() }
    }

    // MARK: - Timing

    private static let minInterval: TimeInterval = 25.0
    private static let maxInterval: TimeInterval = 75.0
    private static let approachDuration: TimeInterval = 2.0
    private static let interactDuration: TimeInterval = 2.5
    private static let retreatDuration: TimeInterval = 1.5

    /// 管理调度和互动流程的 Task，可随时取消
    private var schedulingTask: Task<Void, Never>?
    private var isRunning: Bool = false

    private init() {}

    // MARK: - Public API

    func startScheduling() {
        scheduleNextIfEligible()
    }

    func stopScheduling() {
        schedulingTask?.cancel()
        schedulingTask = nil
        isRunning = false
        phase = .idle
    }

    /// 外部中断 (比如用户拖拽了某个生物)
    func cancelInteraction() {
        guard isRunning else { return }
        schedulingTask?.cancel()
        schedulingTask = nil
        isRunning = false
        phase = .idle
        // 延迟后重新调度
        scheduleAfterDelay(10.0)
    }

    // MARK: - Scheduling

    private func checkAndScheduleIfReady() {
        if crawfishCanInteract && crabCanInteract && schedulingTask == nil && !isRunning {
            scheduleNextIfEligible()
        }
    }

    private func scheduleNextIfEligible() {
        guard crawfishCanInteract, crabCanInteract, schedulingTask == nil, !isRunning else { return }
        let delay = Double.random(in: Self.minInterval...Self.maxInterval)
        scheduleAfterDelay(delay)
    }

    private func scheduleAfterDelay(_ delay: TimeInterval) {
        schedulingTask?.cancel()
        schedulingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.schedulingTask = nil
            self?.triggerInteraction()
        }
    }

    // MARK: - Interaction Flow

    private func triggerInteraction() {
        guard crawfishCanInteract, crabCanInteract, !isRunning else {
            // 条件不满足，重新调度
            scheduleNextIfEligible()
            return
        }

        isRunning = true
        let type = InteractionType.allCases.randomElement()!

        // 会合点: 两者中间偏随机
        meetingX = CGFloat.random(in: 0.35...0.65)

        // 用单个 Task 管理完整互动流程，可随时取消
        schedulingTask = Task { [weak self] in
            // Phase 1: Approaching
            self?.phase = .approaching(type)

            try? await Task.sleep(for: .seconds(Self.approachDuration))
            guard !Task.isCancelled, self?.isRunning == true else { return }

            // Phase 2: Interacting
            self?.phase = .interacting(type)
            self?.fxTrigger += 1

            try? await Task.sleep(for: .seconds(Self.interactDuration))
            guard !Task.isCancelled, self?.isRunning == true else { return }

            // Phase 3: Retreating
            self?.phase = .retreating

            try? await Task.sleep(for: .seconds(Self.retreatDuration))
            guard !Task.isCancelled else { return }

            // Phase 4: Back to idle
            self?.isRunning = false
            self?.phase = .idle
            self?.schedulingTask = nil
            // 调度下一次
            self?.scheduleNextIfEligible()
        }
    }
}
