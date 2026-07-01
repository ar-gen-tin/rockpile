import SwiftUI

struct CrawfishSpriteView: View {
    let state: ClawState
    let isSelected: Bool
    var size: CGFloat = 48
    /// When true, the crayfish flips upside down — "水里没氧气了，翻肚嗝屁"
    var isDead: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bobAmplitude: CGFloat {
        if reduceMotion || isDead { return 0 }
        guard state.bobAmplitude > 0 else { return 0 }
        return isSelected ? state.bobAmplitude : state.bobAmplitude * 0.67
    }

    private static let angryTrembleAmplitude: CGFloat = 0.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || (!isDead && bobAmplitude == 0 && state.emotion != .angry))) { timeline in
            SpriteSheetView(
                spriteSheet: state.spriteSheetName,
                frameCount: isDead ? 1 : state.frameCount, // Freeze on first frame when dead
                columns: isDead ? 1 : state.columns,
                fps: isDead ? 0 : state.animationFPS,      // Stop animation when dead
                isAnimating: !isDead
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isDead ? 180 : 0))     // Flip upside down
            .scaleEffect(x: isDead ? -1 : 1, y: 1)          // Mirror to keep facing right while flipped
            .saturation(isDead ? 0.3 : 1.0)                  // Desaturate when dead
            .opacity(isDead ? 0.7 : 1.0)                     // Slightly transparent
            .overlay(alignment: .center) {
                // "✕‿✕" overlay when dead
                if isDead {
                    Text("✕‿✕")
                        .font(.system(size: size * 0.18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .offset(y: -size * 0.08)
                }
            }
            .offset(
                x: isDead ? 0 : trembleOffset(at: timeline.date, amplitude: state.emotion == .angry ? Self.angryTrembleAmplitude : 0),
                y: isDead
                    ? deadBobOffset(at: timeline.date) // Slow floating drift
                    : bobOffset(at: timeline.date, duration: state.bobDuration, amplitude: bobAmplitude)
            )
        }
        .animation(.easeInOut(duration: 1.0), value: isDead)
    }

    /// Slow, gentle floating motion for the dead crayfish (like floating belly-up)
    private func deadBobOffset(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        // Very slow, gentle undulation — like drifting in still water
        return CGFloat(sin(t * 0.4)) * 2.0 - 3.0 // Slight upward drift
    }
}
