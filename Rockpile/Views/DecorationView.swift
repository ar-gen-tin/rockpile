import SwiftUI

/// 水下像素风装饰物 — 石头、贝壳（可点击）
///
/// 在 PondView 底部渲染，增加场景丰富度。
/// 贝壳点击弹出随机 emoji 彩蛋。
struct DecorationView: View {
    let width: CGFloat
    let height: CGFloat
    /// 海底地面高度 — 装饰物放置在地面表面
    var groundHeight: CGFloat = 0

    @State private var shellOpen: Bool = false
    @State private var shellEmoji: String = ""
    @State private var shellEmojiOpacity: Double = 0
    @State private var shellEmojiOffset: CGFloat = 0
    @State private var shellWiggle: Double = 0

    private static let emojis = ["⭐️", "🦀", "💎", "🐚", "🌟", "🐠"]

    // Fixed positions (fraction of width) — 缩小适配 30% 池塘
    private let stones: [(x: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.18, 10, 5),
        (0.22, 7, 4),
        (0.78, 9, 5),
    ]

    // Coral stones — warm brown/orange tones (寄居蟹壳呼应)
    private let corals: [(x: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.42, 8, 6),
        (0.58, 6, 5),
        (0.65, 9, 6),
    ]

    private let shellX: CGFloat = 0.26

    var body: some View {
        ZStack(alignment: .bottom) {
            // Coral stones (v2.0 — warm tones near hermit crab zone)
            ForEach(Array(corals.enumerated()), id: \.offset) { idx, coral in
                Canvas { context, size in
                    let cx = size.width * coral.x
                    let cy = size.height - groundHeight + 4  // 部分嵌入沙地

                    // Irregular coral shape (rounded, organic)
                    var path = Path()
                    path.addRoundedRect(
                        in: CGRect(x: cx - coral.w / 2, y: cy - coral.h,
                                   width: coral.w, height: coral.h),
                        cornerSize: CGSize(width: 3, height: 3)
                    )
                    // Warm brown-orange hue, varies slightly per coral
                    let hueShift = Double(idx) * 0.02
                    context.fill(path, with: .color(Color(
                        red: 0.55 + hueShift, green: 0.35 + hueShift * 0.5, blue: 0.22
                    ).opacity(0.65)))

                    // Texture highlight (top-left)
                    let hlRect = CGRect(x: cx - coral.w / 2 + 2, y: cy - coral.h + 1, width: 3, height: 2)
                    context.fill(Path(hlRect), with: .color(Color(
                        red: 0.7 + hueShift, green: 0.5, blue: 0.3
                    ).opacity(0.4)))

                    // Small dot texture (pixel granularity)
                    let dotRect = CGRect(x: cx + 1, y: cy - coral.h + 3, width: 2, height: 2)
                    context.fill(Path(dotRect), with: .color(Color(
                        red: 0.45, green: 0.28, blue: 0.18
                    ).opacity(0.35)))
                }
                .allowsHitTesting(false)
            }

            // Stones (static, non-interactive)
            ForEach(Array(stones.enumerated()), id: \.offset) { _, stone in
                Canvas { context, size in
                    let cx = size.width * stone.x
                    let cy = size.height - groundHeight + 3  // 部分嵌入沙地

                    // Irregular pixel stone shape
                    var path = Path()
                    path.addRoundedRect(
                        in: CGRect(x: cx - stone.w / 2, y: cy - stone.h,
                                   width: stone.w, height: stone.h),
                        cornerSize: CGSize(width: 2, height: 2)
                    )
                    context.fill(path, with: .color(Color(red: 0.25, green: 0.25, blue: 0.28).opacity(0.7)))

                    // Highlight pixel on top-left
                    let hlRect = CGRect(x: cx - stone.w / 2 + 2, y: cy - stone.h + 1, width: 3, height: 2)
                    context.fill(Path(hlRect), with: .color(Color(red: 0.4, green: 0.4, blue: 0.45).opacity(0.5)))
                }
                .allowsHitTesting(false)
            }

            // Shell (interactive) — 放在沙地表面
            shellView
                .position(x: width * shellX, y: height - groundHeight + 1)

            // Shell emoji popup
            if !shellEmoji.isEmpty {
                Text(shellEmoji)
                    .font(.system(size: 12))
                    .opacity(shellEmojiOpacity)
                    .offset(x: width * shellX - width / 2, y: -14 + shellEmojiOffset)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var shellView: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let openAngle = shellOpen ? 0.3 : 0.0

            // Bottom half (base)
            var bottom = Path()
            bottom.addEllipse(in: CGRect(x: cx - 5, y: cy - 1, width: 10, height: 6))
            context.fill(bottom, with: .color(Color(red: 0.85, green: 0.7, blue: 0.55).opacity(0.8)))

            // Top half (lid) — rotates when open
            var top = Path()
            top.addEllipse(in: CGRect(x: cx - 5, y: cy - 5 + CGFloat(openAngle * 4), width: 10, height: 5))
            context.fill(top, with: .color(Color(red: 0.95, green: 0.8, blue: 0.65).opacity(0.8)))

            // Ridge lines (pixel decoration)
            for i in 0..<3 {
                let rx = cx - 3 + CGFloat(i) * 3
                let ry = cy - 3 + CGFloat(openAngle * 3)
                let rRect = CGRect(x: rx, y: ry, width: 1, height: 3)
                context.fill(Path(rRect), with: .color(Color(red: 0.7, green: 0.55, blue: 0.4).opacity(0.5)))
            }
        }
        .frame(width: 12, height: 9)
        .rotationEffect(.degrees(shellWiggle))
        .onTapGesture {
            triggerShell()
        }
        .contentShape(Rectangle())
    }

    private func triggerShell() {
        // Open shell
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            shellOpen = true
        }

        // Wiggle
        withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) {
            shellWiggle = 5
        }

        // Show random emoji
        shellEmoji = Self.emojis.randomElement() ?? "⭐️"
        shellEmojiOffset = 0
        shellEmojiOpacity = 1

        withAnimation(.easeOut(duration: 1.0)) {
            shellEmojiOffset = -25
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.7)) {
            shellEmojiOpacity = 0
        }

        // Close shell after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                shellWiggle = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                shellOpen = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            shellEmoji = ""
        }
    }
}
