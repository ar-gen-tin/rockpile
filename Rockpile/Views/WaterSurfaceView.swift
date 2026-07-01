import SwiftUI

/// 像素风水面波浪线 — PondView 顶部装饰
///
/// 参考 Star-Office-UI 的场景装饰动画风格：
/// - 2-3条错开的正弦曲线，像素化渲染
/// - 缓慢左右移动，营造水流感
/// - 15fps 低帧率保持像素感

struct WaterSurfaceView: View {
    let width: CGFloat
    let oxygenLevel: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wave amplitude scales with oxygen level
    private var waveAmplitude: CGFloat {
        CGFloat(max(0.3, oxygenLevel)) * 3.0
    }

    /// Wave color darkens as oxygen drops
    private var waveColor: Color {
        if oxygenLevel > 0.6 {
            return Color(red: 0.3, green: 0.6, blue: 0.85)
        } else if oxygenLevel > 0.3 {
            return Color(red: 0.2, green: 0.5, blue: 0.6)
        } else {
            return Color(red: 0.15, green: 0.35, blue: 0.4)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

                // Draw 3 wave lines at different phases and amplitudes
                let waves: [(phase: Double, amp: CGFloat, yOffset: CGFloat, alpha: Double)] = [
                    (0.0, waveAmplitude * 1.0, 2, 0.5),
                    (2.1, waveAmplitude * 0.7, 5, 0.35),
                    (4.2, waveAmplitude * 0.5, 8, 0.2),
                ]

                for wave in waves {
                    var path = Path()
                    let pixelStep: CGFloat = 4 // Pixel-sized steps for that retro look

                    for x in stride(from: CGFloat(0), through: w, by: pixelStep) {
                        let normalizedX = Double(x / w)
                        let y = wave.yOffset + CGFloat(
                            sin(normalizedX * .pi * 4 + t * 1.2 + wave.phase) * Double(wave.amp)
                        )

                        if x == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            // Pixelated: horizontal then vertical (stair-step)
                            let prevX = x - pixelStep
                            let prevY = wave.yOffset + CGFloat(
                                sin(Double(prevX / w) * .pi * 4 + t * 1.2 + wave.phase) * Double(wave.amp)
                            )
                            // Step pattern for pixel look
                            path.addLine(to: CGPoint(x: x, y: prevY))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(waveColor.opacity(wave.alpha)),
                        lineWidth: 2
                    )
                }

                // Subtle highlight sparkles on the water surface
                let sparkleCount = oxygenLevel > 0.3 ? 5 : 2
                for i in 0..<sparkleCount {
                    let sparkleX = (sin(t * 0.3 + Double(i) * 1.7) * 0.5 + 0.5) * Double(w)
                    let sparkleY = 3.0 + sin(t * 0.5 + Double(i) * 2.3) * Double(waveAmplitude * 0.5)
                    let sparkleAlpha = (sin(t * 2.0 + Double(i) * 3.1) * 0.5 + 0.5) * 0.4

                    let sparkleRect = CGRect(
                        x: sparkleX - 1,
                        y: sparkleY - 1,
                        width: 2,
                        height: 2
                    )
                    context.fill(
                        Path(sparkleRect),
                        with: .color(Color.white.opacity(sparkleAlpha))
                    )
                }
            }
            .frame(width: width, height: 14)
        }
        .allowsHitTesting(false)
    }
}
