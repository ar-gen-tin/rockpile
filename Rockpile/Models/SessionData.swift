import Foundation
import Observation

@MainActor
@Observable
final class SessionData: Identifiable {
    let id: String
    let cwd: String
    let sessionNumber: Int
    let creatureType: CreatureType
    let spriteXPosition: CGFloat
    let spriteYOffset: CGFloat

    private(set) var state: ClawState = .idle
    private(set) var emotionState = EmotionState()
    private(set) var tokenTracker = TokenTracker()
    private(set) var lastEventTime = Date()
    private(set) var activities: [ActivityItem] = []

    private var sleepTimer: Timer?

    /// 当前情绪分析 Task — session 清除时取消
    var emotionTask: Task<Void, Never>?

    private static let sleepTimeout: TimeInterval = RC.Session.sleepTimeout
    private static let xPositionMin: CGFloat = 0.05
    private static let xPositionRange: CGFloat = 0.90
    private static let xMinSeparation: CGFloat = 0.15
    private static let xCollisionRetries = 10
    private static let xNudgeStep: CGFloat = 0.23

    /// Invalidate timers and cancel tasks before removing from session store
    func cleanup() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        emotionTask?.cancel()
        emotionTask = nil
    }

    init(sessionId: String, cwd: String, sessionNumber: Int, creatureType: CreatureType = .crawfish, existingXPositions: [CGFloat] = []) {
        self.id = sessionId
        self.cwd = cwd
        self.sessionNumber = sessionNumber
        self.creatureType = creatureType

        let hash = UInt(abs(sessionId.hashValue))
        self.spriteXPosition = Self.resolveXPosition(hash: hash, existingPositions: existingXPositions)
        self.spriteYOffset = Self.resolveYOffset(hash: hash, creatureType: creatureType)

        tokenTracker.creatureType = creatureType
        resetSleepTimer()
    }

    func updateTask(_ task: ClawTask) {
        state.task = task
        lastEventTime = Date()
        resetSleepTimer()
    }

    func updateEmotion(_ emotion: ClawEmotion) {
        state.emotion = emotion
    }

    func syncEmotion() {
        state.emotion = emotionState.currentEmotion
    }

    func addActivity(_ item: ActivityItem) {
        activities.append(item)
        if activities.count > 50 {
            activities.removeFirst(activities.count - 50)
        }
    }

    private func resetSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Self.sleepTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.state.task = .sleeping
            }
        }
    }

    private static func resolveXPosition(hash: UInt, existingPositions: [CGFloat]) -> CGFloat {
        var candidate = xPositionMin + CGFloat(hash % 900) / 1000.0
        for _ in 0..<xCollisionRetries {
            let tooClose = existingPositions.contains { abs($0 - candidate) < xMinSeparation }
            if !tooClose { break }
            candidate = (candidate + xNudgeStep).truncatingRemainder(dividingBy: xPositionRange) + xPositionMin
        }
        return candidate
    }

    private static func resolveYOffset(hash: UInt, creatureType: CreatureType) -> CGFloat {
        let yBits = (hash >> 8) & 0xFF
        return creatureType.yOffsetBase - CGFloat(yBits % creatureType.yOffsetRange)
    }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ActivityType
    let detail: String

    enum ActivityType {
        case thinking
        case toolCall
        case toolResult
        case error
        case message
        case completion
    }
}
