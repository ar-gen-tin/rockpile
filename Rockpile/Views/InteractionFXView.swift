import SwiftUI

/// 生物互动粒子特效 — 会合点绽放星星/心形
///
/// 复用 TransitionFXView 的 TimelineView + Canvas 模式:
/// - 碰撞: 橙色+青色混合星星爆开
/// - 碰拳: 大号金色星星
/// - 玩耍: 小气泡群
/// - 依偎: 心形粒子
struct InteractionFXView: View {
    let fxTrigger: Int
    let meetingX: CGFloat
    let totalWidth: CGFloat
    let interactionType: InteractionCoordinator.InteractionType?

    @State private var particles: [InteractionParticle] = []
    @State private var animationProgress: Double = 0

    private struct InteractionParticle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let startSize: CGFloat
        let delay: Double
        let color: Color
        let shape: ParticleShape
    }

    private enum ParticleShape {
        case cross   // ✦ 十字星
        case heart   // ❤ 心形
        case circle  // ● 圆点气泡
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: particles.isEmpty)) { timeline in
            Canvas { context, canvasSize in
                guard !particles.isEmpty else { return }

                // 会合点位置: 底部区域
                let centerX = totalWidth * meetingX
                let centerY = canvasSize.height * 0.85

                for particle in particles {
                    let t = min(1.0, max(0, animationProgress - particle.delay) / 0.5)
                    guard t > 0 else { continue }

                    let eased = 1.0 - pow(1.0 - t, 3)
                    let dist = CGFloat(eased) * particle.distance
                    let x = centerX + cos(particle.angle) * dist
                    let y = centerY + sin(particle.angle) * dist
                    let currentSize = particle.startSize * CGFloat(1.0 - eased * 0.6)
                    let alpha = 1.0 - eased

                    switch particle.shape {
                    case .cross:
                        let half = currentSize / 2
                        let hRect = CGRect(x: x - half, y: y - 1, width: currentSize, height: 2)
                        let vRect = CGRect(x: x - 1, y: y - half, width: 2, height: currentSize)
                        context.fill(Path(hRect), with: .color(particle.color.opacity(alpha)))
                        context.fill(Path(vRect), with: .color(particle.color.opacity(alpha)))
                        // Center pixel — 使用粒子自身颜色，避免白斑
                        let cRect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Path(cRect), with: .color(particle.color.opacity(alpha * 0.9)))

                    case .heart:
                        let text = Text("\u{2764}\u{FE0F}").font(.system(size: currentSize))
                        context.draw(text, at: CGPoint(x: x, y: y))

                    case .circle:
                        let rect = CGRect(x: x - currentSize / 2, y: y - currentSize / 2,
                                          width: currentSize, height: currentSize)
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(particle.color.opacity(alpha * 0.7)),
                            lineWidth: 0.8
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: fxTrigger) { _, _ in
            spawnParticles()
        }
    }

    private func spawnParticles() {
        guard let type = interactionType else { return }

        var newParticles: [InteractionParticle] = []
        let count: Int
        let shape: ParticleShape
        let colors: [Color]

        switch type {
        case .bump:
            count = 6
            shape = .cross
            colors = [DS.Semantic.localAccent, DS.Semantic.remoteAccent]
        case .highFive:
            count = 8
            shape = .cross
            colors = [.yellow, .orange]
        case .play:
            count = 5
            shape = .circle
            colors = [Color(red: 0.5, green: 0.78, blue: 0.95)]
        case .nuzzle:
            count = 4
            shape = .heart
            colors = [.pink, .red]
        }

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * .pi * 2 + Double.random(in: -0.4...0.4)
            newParticles.append(InteractionParticle(
                angle: angle,
                distance: CGFloat.random(in: 15...40),
                startSize: CGFloat.random(in: 4...9),
                delay: Double(i) * 0.03,
                color: colors.randomElement()!,
                shape: shape
            ))
        }

        particles = newParticles
        animationProgress = 0

        withAnimation(.linear(duration: 0.6)) {
            animationProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            particles = []
            animationProgress = 0
        }
    }
}
