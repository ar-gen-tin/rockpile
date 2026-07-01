import SwiftUI

/// 状态转场星星粒子特效 — 龙虾切换状态时爆发像素星星
///
/// 参考 Star-Office-UI 角色切换区域时的视觉反馈：
/// - 4-6个白色像素十字星 ✦ 从中心爆开
/// - 快速扩散后消失（0.4s 总时长）
/// - 颜色跟随状态语义色

struct TransitionFXView: View {
    let triggerCounter: Int
    let stateColor: Color
    let size: CGFloat

    @State private var particles: [StarParticle] = []
    @State private var animationProgress: Double = 0

    private struct StarParticle: Identifiable {
        let id = UUID()
        let angle: Double     // Direction in radians
        let distance: CGFloat // Max travel distance
        let startSize: CGFloat
        let delay: Double     // Stagger start
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: particles.isEmpty)) { timeline in
            Canvas { context, canvasSize in
                guard !particles.isEmpty else { return }

                let centerX = canvasSize.width / 2
                let centerY = canvasSize.height / 2

                for particle in particles {
                    let t = min(1.0, max(0, animationProgress - particle.delay) / 0.35)
                    guard t > 0 else { continue }

                    // Ease out: fast start, slow end
                    let eased = 1.0 - pow(1.0 - t, 3)

                    let dist = CGFloat(eased) * particle.distance
                    let x = centerX + cos(particle.angle) * dist
                    let y = centerY + sin(particle.angle) * dist

                    // Size shrinks as it moves out
                    let currentSize = particle.startSize * CGFloat(1.0 - eased * 0.7)

                    // Opacity fades out
                    let alpha = 1.0 - eased

                    // Draw pixel cross ✦ shape
                    let half = currentSize / 2

                    // Horizontal bar
                    let hRect = CGRect(x: x - half, y: y - 1, width: currentSize, height: 2)
                    // Vertical bar
                    let vRect = CGRect(x: x - 1, y: y - half, width: 2, height: currentSize)

                    context.fill(Path(hRect), with: .color(stateColor.opacity(alpha)))
                    context.fill(Path(vRect), with: .color(stateColor.opacity(alpha)))

                    // Center bright pixel — 使用状态色而非纯白，避免像素艺术上的白斑
                    let cRect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    context.fill(Path(cRect), with: .color(stateColor.opacity(alpha * 0.9)))
                }
            }
        }
        .frame(width: size * 2, height: size * 2)
        .allowsHitTesting(false)
        .onChange(of: triggerCounter) { _, _ in
            spawnParticles()
        }
    }

    private func spawnParticles() {
        let count = Int.random(in: 4...6)
        var newParticles: [StarParticle] = []

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * .pi * 2 + Double.random(in: -0.3...0.3)
            newParticles.append(StarParticle(
                angle: angle,
                distance: CGFloat.random(in: size * 0.3...size * 0.7),
                startSize: CGFloat.random(in: 4...8),
                delay: Double(i) * 0.02
            ))
        }

        particles = newParticles
        animationProgress = 0

        // Animate progress
        withAnimation(.linear(duration: 0.4)) {
            animationProgress = 1.0
        }

        // Clear particles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            particles = []
            animationProgress = 0
        }
    }
}
