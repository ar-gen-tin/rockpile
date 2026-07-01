import SwiftUI

/// 灵魂出窍效果 — 龙虾死亡时半透明幽灵从身体向上飘出
///
/// - 半透明（0.35 opacity）白色调龙虾精灵
/// - 缓慢向上飘动 + 左右摆动
/// - 3秒后完全消失
/// - 通过 onChange(of: isDead) 内部触发

struct GhostSpriteView: View {
    let state: ClawState
    let size: CGFloat
    let isDead: Bool

    @State private var ghostOffset: CGFloat = 0
    @State private var ghostOpacity: Double = 0
    @State private var ghostActive = false

    var body: some View {
        Group {
            if ghostActive {
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let sway = CGFloat(sin(t * 1.5)) * 3

                    SpriteSheetView(
                        spriteSheet: state.spriteSheetName,
                        frameCount: 1,
                        columns: 1,
                        fps: 0,
                        isAnimating: false
                    )
                    .frame(width: size * 0.7, height: size * 0.7)
                    .saturation(0)
                    .brightness(0.3)
                    .opacity(ghostOpacity * 0.35)
                    .offset(x: sway, y: ghostOffset)
                }
            }
        }
        .onChange(of: isDead) { _, dead in
            if dead {
                triggerGhost()
            }
        }
    }

    private func triggerGhost() {
        ghostActive = true
        ghostOffset = 0
        ghostOpacity = 1.0

        withAnimation(.easeOut(duration: 3.0)) {
            ghostOffset = -size * 0.8
            ghostOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            ghostActive = false
        }
    }
}
