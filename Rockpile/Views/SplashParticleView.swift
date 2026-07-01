import SwiftUI

/// 入水水花粒子 — 展开面板时龙虾跳入水中的溅水效果
///
/// 3-5个白色小方块向上散开后消失，模拟像素水花。

struct SplashParticleView: View {
    let isActive: Bool
    let origin: CGPoint // Where the splash happens
    let size: CGFloat

    @State private var splashDrops: [SplashDrop] = []

    private struct SplashDrop: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var velocityX: CGFloat
        var velocityY: CGFloat
        var alpha: Double
        var pixelSize: CGFloat
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: splashDrops.isEmpty)) { timeline in
            Canvas { context, canvasSize in
                for drop in splashDrops {
                    guard drop.alpha > 0.05 else { continue }
                    let rect = CGRect(
                        x: drop.x - drop.pixelSize / 2,
                        y: drop.y - drop.pixelSize / 2,
                        width: drop.pixelSize,
                        height: drop.pixelSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(Color(red: 0.6, green: 0.8, blue: 1.0).opacity(drop.alpha))
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active {
                triggerSplash()
            }
        }
    }

    private func triggerSplash() {
        let count = Int.random(in: 4...6)
        var drops: [SplashDrop] = []

        for _ in 0..<count {
            drops.append(SplashDrop(
                x: origin.x + CGFloat.random(in: -8...8),
                y: origin.y,
                velocityX: CGFloat.random(in: -3...3),
                velocityY: CGFloat.random(in: (-6)...(-2)),
                alpha: 1.0,
                pixelSize: CGFloat.random(in: 2...4)
            ))
        }

        splashDrops = drops

        // Animate drops over 0.5s
        animateDrops(step: 0)
    }

    private func animateDrops(step: Int) {
        guard step < 15 else {
            splashDrops = []
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) {
            for i in splashDrops.indices {
                splashDrops[i].x += splashDrops[i].velocityX
                splashDrops[i].y += splashDrops[i].velocityY
                splashDrops[i].velocityY += 0.5 // gravity
                splashDrops[i].alpha -= 0.07
            }
            animateDrops(step: step + 1)
        }
    }
}
