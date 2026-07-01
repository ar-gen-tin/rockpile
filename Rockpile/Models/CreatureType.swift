import Foundation

/// Distinguishes local Claude Code (hermit crab) from remote Openclaw (crawfish).
enum CreatureType: String, Codable, Sendable {
    case hermitCrab  // 本地 Claude Code → 寄居蟹
    case crawfish    // 远程 Openclaw → 小龙虾

    /// Non-localized display name (safe from any isolation, for logging etc.)
    var displayName: String {
        switch self {
        case .hermitCrab: return "Hermit Crab"
        case .crawfish:   return "Crawfish"
        }
    }

    /// L10n key for localized name (use from @MainActor context)
    var displayNameKey: String {
        switch self {
        case .hermitCrab: return "creature.hermitCrab"
        case .crawfish:   return "creature.crawfish"
        }
    }

    var icon: String {
        switch self {
        case .hermitCrab: return "\u{1F41A}"  // 🐚
        case .crawfish:   return "\u{1F99E}"  // 🦞
        }
    }

    /// Prefix for sprite sheet asset names.
    /// hermitCrab → "crab_idle_neutral", crawfish → "idle_neutral" (legacy)
    var spritePrefix: String {
        switch self {
        case .hermitCrab: return "crab"
        case .crawfish:   return ""  // legacy: no prefix
        }
    }

    // MARK: - Position Zone

    /// Y offset range for pond rendering.
    /// Hermit crabs stay near bottom; crawfish swim mid-water.
    var yOffsetBase: CGFloat {
        switch self {
        case .hermitCrab: return -5.0
        case .crawfish:   return -20.0
        }
    }

    var yOffsetRange: UInt {
        switch self {
        case .hermitCrab: return 11   // -5 ~ -15
        case .crawfish:   return 31   // -20 ~ -50
        }
    }
}

/// Marks the origin of a socket event — local Unix socket or remote TCP.
enum EventSource: String, Sendable {
    case unixSocket  // 本地 → hermitCrab
    case tcpSocket   // 远程 → crawfish
    case gateway     // Gateway WebSocket → crawfish

    var creatureType: CreatureType {
        switch self {
        case .unixSocket: return .hermitCrab
        case .tcpSocket:  return .crawfish
        case .gateway:    return .crawfish
        }
    }
}
