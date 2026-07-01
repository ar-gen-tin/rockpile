import SwiftUI

/// 喂食时食物粒子从水面掉落到龙虾的动画
///
/// 3-5 个小像素块从顶部掉落，带重力加速和水中减速效果。
/// 到达目标 Y 位置后消失。
struct FoodParticleView: View {
    /// Increment to trigger a new feeding animation
    let triggerCounter: Int
    /// Target Y position (sprite center, relative to view)
    let targetY: CGFloat
    /// View size
    let size: CGFloat

    @State private var particles: [FoodParticle] = []
    @State private var animationTime: Double = 0

    private struct FoodParticle: Identifiable {
        let id = UUID()
        let startX: CGFloat
        let xDrift: CGFloat   // Slight horizontal drift
        let speed: Double     // Fall speed multiplier
        let pixelSize: CGFloat
        let color: Color
    }

    private static let foodColors: [Color] = [
        Color(red: 0.85, green: 0.55, blue: 0.25),  // Orange (shrimp)
        Color(red: 0.75, green: 0.45, blue: 0.20),  // Dark orange
        Color(red: 0.90, green: 0.65, blue: 0.30),  // Light orange
        Color(red: 0.65, green: 0.40, blue: 0.15),  // Brown
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: particles.isEmpty)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                guard !particles.isEmpty else { return }
                let elapsed = t - animationTime

                for particle in particles {
                    // Gravity + water resistance: fast acceleration, then slowdown
                    let rawProgress = elapsed * particle.speed
                    // Ease: fast start (gravity), slow end (water resistance)
                    let progress = min(1.0, rawProgress * rawProgress * 0.5 + rawProgress * 0.3)

                    let x = particle.startX + sin(elapsed * 2 + Double(particle.xDrift)) * 3
                    let y = -5 + CGFloat(progress) * (targetY + 10)

                    guard y < targetY + 5 else { continue }

                    let pSize = particle.pixelSize * CGFloat(max(0.5, 1.0 - progress * 0.3))
                    let alpha = max(0, 1.0 - progress * 0.8)

                    let rect = CGRect(x: x - pSize / 2, y: y - pSize / 2, width: pSize, height: pSize)
                    context.fill(Path(rect), with: .color(particle.color.opacity(alpha)))

                    // Tiny highlight pixel
                    let hlRect = CGRect(x: x - pSize / 2, y: y - pSize / 2, width: max(1, pSize * 0.4), height: max(1, pSize * 0.4))
                    context.fill(Path(hlRect), with: .color(Color.white.opacity(alpha * 0.4)))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onChange(of: triggerCounter) { _, _ in
            spawnFood()
        }
    }

    private func spawnFood() {
        let count = Int.random(in: 3...5)
        var newParticles: [FoodParticle] = []

        let centerX = size / 2

        for _ in 0..<count {
            newParticles.append(FoodParticle(
                startX: centerX + CGFloat.random(in: -15...15),
                xDrift: CGFloat.random(in: -3...3),
                speed: Double.random(in: 0.6...1.2),
                pixelSize: CGFloat.random(in: 2.5...4.5),
                color: Self.foodColors.randomElement() ?? .orange
            ))
        }

        particles = newParticles
        animationTime = Date.timeIntervalSinceReferenceDate

        // Clear particles after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            particles = []
        }
    }
}
