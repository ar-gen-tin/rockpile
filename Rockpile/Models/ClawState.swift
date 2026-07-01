import AppKit
import SwiftUI

enum ClawTask: String, CaseIterable {
    case idle, thinking, working, waiting, error, compacting, sleeping

    var animationFPS: Double {
        switch self {
        case .compacting: return 6.0
        case .sleeping:   return 2.0
        case .idle, .waiting: return 3.0
        case .thinking:   return 4.0
        case .working:    return 5.0
        case .error:      return 2.0
        }
    }

    var spritePrefix: String { rawValue }

    var bobDuration: Double {
        switch self {
        case .sleeping:           return 4.0
        case .idle, .waiting:     return 1.5
        case .thinking:           return 1.0
        case .working:            return 0.4
        case .compacting:         return 0.5
        case .error:              return 0.8
        }
    }

    var bobAmplitude: CGFloat {
        switch self {
        case .sleeping, .compacting: return 0
        case .idle:                  return 1.5
        case .thinking:              return 0.8
        case .waiting:               return 0.5
        case .working:               return 0.5
        case .error:                 return 0.3
        }
    }

    var canWalk: Bool {
        switch self {
        case .sleeping, .compacting, .waiting, .error:
            return false
        case .idle, .thinking, .working:
            return true
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .idle:       return L10n.s("state.idle")
        case .thinking:   return L10n.s("state.thinking")
        case .working:    return L10n.s("state.working")
        case .sleeping:   return L10n.s("state.sleeping")
        case .compacting: return L10n.s("state.compacting")
        case .waiting:    return L10n.s("state.waiting")
        case .error:      return L10n.s("state.error")
        }
    }

    /// Canonical status color — single source of truth for all UI
    var statusColor: Color {
        switch self {
        case .idle:       return .gray
        case .thinking:   return DS.Semantic.thinking
        case .working:    return DS.Semantic.working
        case .waiting:    return DS.Semantic.warning
        case .error:      return DS.Semantic.danger
        case .compacting: return .purple
        case .sleeping:   return .gray.opacity(0.5)
        }
    }

    var walkFrequencyRange: ClosedRange<Double> {
        switch self {
        case .sleeping, .waiting: return 30.0...60.0
        case .idle:               return 8.0...15.0
        case .thinking:           return 6.0...14.0
        case .working:            return 5.0...12.0
        case .compacting:         return 15.0...25.0
        case .error:              return 30.0...60.0
        }
    }

    var frameCount: Int {
        switch self {
        case .compacting: return 10
        default: return 12
        }
    }

    var columns: Int {
        switch self {
        case .compacting: return 10
        default: return 12
        }
    }
}

enum ClawEmotion: String, CaseIterable {
    case neutral, happy, sad, angry

    var swayAmplitude: Double {
        switch self {
        case .neutral: return 0.5
        case .happy:   return 1.0
        case .sad:     return 0.25
        case .angry:   return 0.15
        }
    }
}

struct ClawState: Equatable {
    var task: ClawTask
    var emotion: ClawEmotion = .neutral

    /// Cache for resolved sprite sheet names — avoids NSImage(named:) lookup on every frame.
    /// Thread-safe via NSLock (CodexBar IconCacheStore pattern).
    /// `nonisolated(unsafe)` tells Swift 6 that we handle synchronization ourselves.
    private static let _cacheLock = NSLock()
    nonisolated(unsafe) private static var _resolvedNames: [String: String] = [:]

    /// Resolves sprite sheet name with fallback: exact -> sad (for angry) -> neutral.
    /// Default (crawfish) uses legacy naming: "idle_neutral".
    var spriteSheetName: String {
        spriteSheetName(for: .crawfish)
    }

    /// Resolves sprite sheet name for a given creature type.
    /// hermitCrab → "crab_idle_neutral", crawfish → "idle_neutral" (legacy)
    func spriteSheetName(for creature: CreatureType) -> String {
        let key = "\(creature.rawValue)_\(task.rawValue)_\(emotion.rawValue)"
        if let cached = Self._cacheLock.withLock({ Self._resolvedNames[key] }) { return cached }

        let prefix = creature.spritePrefix
        let base = prefix.isEmpty ? task.spritePrefix : "\(prefix)_\(task.spritePrefix)"

        let resolved: String
        let name = "\(base)_\(emotion.rawValue)"
        if NSImage(named: name) != nil {
            resolved = name
        } else if emotion == .angry, NSImage(named: "\(base)_sad") != nil {
            resolved = "\(base)_sad"
        } else {
            resolved = "\(base)_neutral"
        }

        Self._cacheLock.withLock { Self._resolvedNames[key] = resolved }
        return resolved
    }

    var animationFPS: Double { task.animationFPS }
    var bobDuration: Double { task.bobDuration }
    var bobAmplitude: CGFloat {
        switch emotion {
        case .angry: return 0
        case .sad:   return task.bobAmplitude * 0.5
        default:     return task.bobAmplitude
        }
    }
    var swayAmplitude: Double { emotion.swayAmplitude }
    var canWalk: Bool { emotion == .angry ? false : task.canWalk }
    @MainActor var displayName: String { task.displayName }
    var walkFrequencyRange: ClosedRange<Double> { task.walkFrequencyRange }
    var frameCount: Int { task.frameCount }
    var columns: Int { task.columns }

    static let idle = ClawState(task: .idle)
    static let thinking = ClawState(task: .thinking)
    static let working = ClawState(task: .working)
    static let sleeping = ClawState(task: .sleeping)
    static let compacting = ClawState(task: .compacting)
    static let waiting = ClawState(task: .waiting)
    static let error = ClawState(task: .error)
}
