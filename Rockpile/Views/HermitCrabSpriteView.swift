import SwiftUI

/// 寄居蟹精灵渲染 — 与 CrawfishSpriteView 对应的本地生物
///
/// 差异化行为:
/// - 更慢的上下摆动（idle 3.0s, working 1.0s）
/// - 壳微微左右摇晃（±3° sine wave）
/// - 死亡: 缩进壳里(scale 0.7) + 灰色化（不翻肚）
struct HermitCrabSpriteView: View {
    let state: ClawState
    let isSelected: Bool
    var size: CGFloat = 48
    var isDead: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ── Bob parameters (slower than crawfish) ──

    private var bobAmplitude: CGFloat {
        if reduceMotion || isDead { return 0 }
        let base: CGFloat = {
            switch state.task {
            case .sleeping, .compacting: return 0
            case .idle:                  return 0.8
            case .thinking:              return 0.5
            case .waiting:               return 0.3
            case .working:               return 0.3
            case .error:                 return 0.15
            }
        }()
        return isSelected ? base : base * 0.67
    }

    private var bobDuration: Double {
        switch state.task {
        case .sleeping:           return 5.0
        case .idle, .waiting:     return 3.0
        case .thinking:           return 2.0
        case .working:            return 1.0
        case .compacting:         return 1.2
        case .error:              return 1.5
        }
    }

    /// Shell wobble period (seconds per full oscillation)
    private var wobblePeriod: Double {
        switch state.task {
        case .idle, .waiting:  return 4.0
        case .thinking:        return 2.5
        case .working:         return 1.5
        case .sleeping:        return 6.0
        default:               return 3.0
        }
    }

    /// Shell wobble max degrees
    private var wobbleAmplitude: Double {
        if reduceMotion || isDead { return 0 }
        switch state.task {
        case .idle:      return 3.0
        case .thinking:  return 2.0
        case .working:   return 1.5
        case .sleeping:  return 1.0
        default:         return 0
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || (!isDead && bobAmplitude == 0 && wobbleAmplitude == 0))) { timeline in
            SpriteSheetView(
                spriteSheet: state.spriteSheetName(for: .hermitCrab),
                frameCount: isDead ? 1 : state.frameCount,
                columns: isDead ? 1 : state.columns,
                fps: isDead ? 0 : crabFPS,
                isAnimating: !isDead
            )
            .frame(width: size, height: size)
            // Shell wobble rotation
            .rotationEffect(.degrees(wobbleOffset(at: timeline.date)))
            // Death: shrink into shell
            .scaleEffect(isDead ? 0.7 : 1.0)
            .saturation(isDead ? 0.2 : 1.0)
            .opacity(isDead ? 0.6 : 1.0)
            .overlay(alignment: .center) {
                // Shell-closed indicator when dead
                if isDead {
                    Text("💤")
                        .font(.system(size: size * 0.2))
                        .offset(y: -size * 0.15)
                        .opacity(0.7)
                }
            }
            .offset(y: isDead ? 0 : bobOffset(at: timeline.date))
        }
        .animation(.easeInOut(duration: 1.0), value: isDead)
    }

    /// Crab animation FPS — slower than crawfish
    private var crabFPS: Double {
        switch state.task {
        case .compacting: return 4.0
        case .sleeping:   return 1.5
        case .idle, .waiting: return 2.0
        case .thinking:   return 3.0
        case .working:    return 3.5
        case .error:      return 1.5
        }
    }

    // MARK: - Animation Helpers

    private func bobOffset(at date: Date) -> CGFloat {
        guard bobAmplitude > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = t / bobDuration * 2 * .pi
        return CGFloat(sin(phase)) * bobAmplitude
    }

    private func wobbleOffset(at date: Date) -> Double {
        guard wobbleAmplitude > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = t / wobblePeriod * 2 * .pi
        return sin(phase) * wobbleAmplitude
    }
}
