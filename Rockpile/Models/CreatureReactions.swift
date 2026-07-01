import Foundation

/// 生物互动反应系统 — 状态感知 + 个性差异化 (i18n via L10n)
@MainActor
enum CreatureReactions {

    // MARK: - Single Tap

    static func tapReaction(creature: CreatureType, task: ClawTask, isDead: Bool) -> String? {
        guard !isDead else { return nil }
        let prefix = creature == .crawfish ? "rx.crawfish.tap" : "rx.crab.tap"
        return L10n.r("\(prefix).\(task.rawValue)")
    }

    // MARK: - Double Tap (Love)

    static func loveReaction(creature: CreatureType, task: ClawTask, isDead: Bool) -> String? {
        guard !isDead else { return nil }
        let prefix = creature == .crawfish ? "rx.crawfish.love" : "rx.crab.love"
        let key: String
        switch task {
        case .idle, .waiting:   key = "idle"
        case .working, .thinking: key = "working"
        case .sleeping:         key = "sleeping"
        case .error:            key = "error"
        case .compacting:       key = "compacting"
        }
        return L10n.r("\(prefix).\(key)")
    }

    // MARK: - Feed

    static func feedReaction(creature: CreatureType, isOverfed: Bool) -> String {
        let prefix = creature == .crawfish ? "rx.crawfish" : "rx.crab"
        return L10n.r(isOverfed ? "\(prefix).feed.overfed" : "\(prefix).feed")
    }

    // MARK: - Punishment

    static func punishReaction(creature: CreatureType) -> String {
        L10n.r(creature == .crawfish ? "rx.crawfish.punish" : "rx.crab.punish")
    }

    // MARK: - Cross-Creature Interaction

    static func interactionReaction(creature: CreatureType, type: InteractionCoordinator.InteractionType) -> String {
        let prefix = creature == .crawfish ? "rx.crawfish.interact" : "rx.crab.interact"
        return L10n.r("\(prefix).\(type.rawValue)")
    }

    // MARK: - Overfeed Thresholds

    static let overfeedThreshold: Int = 3
    static let overfeedWindow: TimeInterval = 180.0
    static let overfeedRecovery: TimeInterval = 120.0
}
