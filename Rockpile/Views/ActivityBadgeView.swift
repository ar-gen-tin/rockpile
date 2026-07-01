import SwiftUI

/// 远程活动通知气泡 — 展开后小龙虾上方弹出的 "+N" 气泡
///
/// 显示流程：
/// 1. PondView onAppear → consumeForBubble() → 气泡弹入 (spring pop)
/// 2. 停留 4 秒
/// 3. 淡出消失 → pendingCount 清零
struct ActivityBadgeView: View {
    let bubbleCount: Int
    let isBubbleShowing: Bool
    let bubbleTrigger: Int
    let spriteSize: CGFloat

    @State private var badgeScale: CGFloat = 0

    var body: some View {
        if bubbleCount > 0 {
            let label = bubbleCount > 9 ? "+N" : "+\(bubbleCount)"
            HStack(spacing: DS.Space.xxs) {
                Text("📱")
                    .font(DS.Font.tiny)
                Text(label)
                    .font(DS.Font.monoBold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Semantic.info.opacity(DS.Opacity.primary))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(Color.white.opacity(DS.Opacity.tertiary), lineWidth: 0.5)
                    )
            )
            .scaleEffect(badgeScale)
            .opacity(isBubbleShowing ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.4), value: isBubbleShowing)
            .offset(y: -spriteSize * 0.55)
            .allowsHitTesting(false)
            .onAppear {
                popIn()
            }
            .onChange(of: bubbleTrigger) { _, _ in
                popIn()
            }
        }
    }

    private func popIn() {
        badgeScale = 0.3
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            badgeScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.65)) {
                badgeScale = 1.0
            }
        }
    }
}
