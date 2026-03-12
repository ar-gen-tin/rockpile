import SwiftUI

// MARK: - Ocean Floor (SpongeBob-style)

/// 海绵宝宝风格海底沙地 — 暖色沙地 + 纹理 + 小石子
/// 提供视觉对比，让寄居蟹在沙地上清晰可见
struct OceanFloorView: View {
    let width: CGFloat
    let height: CGFloat

    /// 地面高度 (从底部算起) — 增大以提供更明显的海底对比
    static let groundHeight: CGFloat = 30

    var body: some View {
        Canvas { context, size in
            let gh = Self.groundHeight
            let groundTop = size.height - gh

            // ── 1. Main sand body with undulating surface ──
            var sandPath = Path()
            sandPath.move(to: CGPoint(x: 0, y: size.height))
            sandPath.addLine(to: CGPoint(x: 0, y: groundTop + Self.hillY(at: 0)))

            let segments = 24
            for i in 1...segments {
                let x = CGFloat(i) / CGFloat(segments) * size.width
                let y = groundTop + Self.hillY(at: CGFloat(i))
                sandPath.addLine(to: CGPoint(x: x, y: y))
            }
            sandPath.addLine(to: CGPoint(x: size.width, y: size.height))
            sandPath.closeSubpath()

            // Warm tan gradient fill
            context.fill(sandPath, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.82, green: 0.68, blue: 0.48),  // Light warm sand
                    Color(red: 0.72, green: 0.58, blue: 0.40),  // Mid sand
                    Color(red: 0.58, green: 0.44, blue: 0.30),  // Darker base
                ]),
                startPoint: CGPoint(x: size.width / 2, y: groundTop),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))

            // ── 2. Surface highlight line (top edge of sand) ──
            var edgePath = Path()
            edgePath.move(to: CGPoint(x: 0, y: groundTop + Self.hillY(at: 0)))
            for i in 1...segments {
                let x = CGFloat(i) / CGFloat(segments) * size.width
                let y = groundTop + Self.hillY(at: CGFloat(i))
                edgePath.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(edgePath, with: .color(
                Color(red: 0.90, green: 0.78, blue: 0.58).opacity(0.7)
            ), lineWidth: 1.5)

            // ── 3. Sand texture specks (deterministic positions) ──
            for i in 0..<30 {
                let fx = fmod(CGFloat(i) * 14.7 + 3.2, size.width)
                let fy = groundTop + 5 + fmod(CGFloat(i) * 4.3 + 1.1, gh - 6)
                let ds: CGFloat = CGFloat(i % 3 + 1) * 0.6
                context.fill(
                    Path(CGRect(x: fx, y: fy, width: ds, height: ds)),
                    with: .color(Color(red: 0.50, green: 0.38, blue: 0.26).opacity(0.3))
                )
            }

            // ── 4. Lighter sand patches near surface ──
            for i in 0..<12 {
                let fx = fmod(CGFloat(i) * 38.5 + 10.3, size.width)
                let fy = groundTop + Self.hillY(at: CGFloat(i) * 2) + 3
                let pw: CGFloat = CGFloat(i % 3 + 3) * 1.5
                let ph: CGFloat = pw * 0.4
                context.fill(
                    Path(ellipseIn: CGRect(x: fx - pw / 2, y: fy, width: pw, height: ph)),
                    with: .color(Color(red: 0.90, green: 0.78, blue: 0.60).opacity(0.35))
                )
            }

            // ── 5. Small embedded pebbles ──
            let pebbles: [(x: CGFloat, yF: CGFloat, w: CGFloat, h: CGFloat, dark: Bool)] = [
                (0.08, 0.40, 3.5, 2.0, true),
                (0.25, 0.55, 2.5, 1.8, false),
                (0.38, 0.35, 4.0, 2.5, true),
                (0.55, 0.50, 3.0, 2.0, false),
                (0.72, 0.38, 3.5, 2.2, true),
                (0.88, 0.45, 2.8, 1.8, false),
            ]
            for p in pebbles {
                let px = size.width * p.x
                let py = groundTop + gh * p.yF
                let r = CGRect(x: px - p.w / 2, y: py, width: p.w, height: p.h)
                let color = p.dark
                    ? Color(red: 0.40, green: 0.32, blue: 0.22)
                    : Color(red: 0.55, green: 0.45, blue: 0.32)
                context.fill(Path(ellipseIn: r), with: .color(color.opacity(0.5)))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    /// Deterministic hill profile for undulating sand surface
    private static func hillY(at i: CGFloat) -> CGFloat {
        let a = sin(Double(i) * 0.5 + 0.3) * 2.5
        let b = sin(Double(i) * 1.1 + 1.8) * 1.2
        return CGFloat(a + b)
    }
}

// MARK: - Seaweed

struct SeaweedCluster: View {
    let size: CGSize

    init(in size: CGSize) {
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Left seaweed cluster (缩小适配 30% 池塘)
            SeaweedStalk(height: 25, sway: 2)
                .offset(x: -size.width * 0.38, y: 0)
            SeaweedStalk(height: 18, sway: 1.5)
                .offset(x: -size.width * 0.35, y: 0)

            // Right seaweed cluster
            SeaweedStalk(height: 28, sway: 2.5)
                .offset(x: size.width * 0.35, y: 0)
            SeaweedStalk(height: 20, sway: 1.5)
                .offset(x: size.width * 0.38, y: 0)

            // Far left single
            SeaweedStalk(height: 15, sway: 1)
                .offset(x: -size.width * 0.45, y: 0)
                .opacity(0.6)

            // Far right single
            SeaweedStalk(height: 17, sway: 1.2)
                .offset(x: size.width * 0.44, y: 0)
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct SeaweedStalk: View {
    let height: CGFloat
    let sway: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let swayOffset = sin(t * 0.8) * sway

            Canvas { context, canvasSize in
                var path = Path()
                let baseX = canvasSize.width / 2
                let baseY = canvasSize.height
                let segments = 6

                path.move(to: CGPoint(x: baseX, y: baseY))

                for i in 1...segments {
                    let frac = CGFloat(i) / CGFloat(segments)
                    let x = baseX + sin(frac * .pi * 1.2) * sway + swayOffset * frac
                    let y = baseY - height * frac
                    let cpX = baseX + sin((frac - 0.08) * .pi * 1.2) * sway * 0.8
                    let cpY = baseY - height * (frac - 0.05)
                    path.addQuadCurve(to: CGPoint(x: x, y: y),
                                      control: CGPoint(x: cpX, y: cpY))
                }

                context.stroke(
                    path,
                    with: .color(Color(red: 0.1, green: 0.45, blue: 0.2).opacity(0.7)),
                    lineWidth: 3
                )
                // Draw leaf blobs
                for i in stride(from: 2, through: segments, by: 2) {
                    let frac = CGFloat(i) / CGFloat(segments)
                    let x = baseX + sin(frac * .pi * 1.2) * sway + swayOffset * frac
                    let y = baseY - height * frac

                    let leafRect = CGRect(x: x - 5, y: y - 3, width: 10, height: 6)
                    context.fill(
                        Path(ellipseIn: leafRect),
                        with: .color(Color(red: 0.12, green: 0.5, blue: 0.25).opacity(0.6))
                    )
                }
            }
            .frame(width: 30, height: height + 10)
        }
    }
}
