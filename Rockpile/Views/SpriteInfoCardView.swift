import SwiftUI

/// 长按龙虾时显示的像素风信息卡
///
/// ┌──────────────────────┐
/// │ ⚡ 工作中              │
/// │ O₂ 85% · 已用 2.0K   │
/// └──────────────────────┘
struct SpriteInfoCardView: View {
    let state: ClawState
    let oxygenLevel: Double
    let sessionTokens: Int
    let isVisible: Bool
    var burnRateText: String?
    var etaText: String?

    @State private var opacity: Double = 0

    private var taskIcon: String {
        switch state.task {
        case .idle:       return "😴"
        case .thinking:   return "🤔"
        case .working:    return "⚡"
        case .waiting:    return "👀"
        case .error:      return "❗"
        case .compacting: return "🗜️"
        case .sleeping:   return "💤"
        }
    }

    private var oxygenColor: Color {
        if oxygenLevel >= 0.6 { return DS.Semantic.success }
        if oxygenLevel >= 0.3 { return DS.Semantic.warning }
        return DS.Semantic.danger
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                // Line 1: Status icon + Chinese label
                Text("\(taskIcon) \(state.displayName)")
                    .font(DS.Font.secondary)
                    .foregroundColor(.white)

                // Line 2: O₂ + Session tokens
                HStack(spacing: DS.Space.xs) {
                    Circle()
                        .fill(oxygenColor)
                        .frame(width: 5, height: 5)
                    Text("O\u{2082} \(Int(oxygenLevel * 100))%")
                        .font(DS.Font.monoSmall)
                        .foregroundColor(oxygenColor)
                    if sessionTokens > 0 {
                        Text("·")
                            .foregroundColor(DS.TextColor.tertiary)
                        Text("\(L10n.s("o2.used")) \(TokenTracker.formatTokens(sessionTokens))")
                            .font(DS.Font.monoSmall)
                            .foregroundColor(DS.TextColor.secondary)
                    }
                }

                // Line 3: Burn rate + ETA (仅活跃时显示)
                if let rate = burnRateText {
                    HStack(spacing: DS.Space.xs) {
                        Text(rate)
                            .font(DS.Font.monoSmall)
                            .foregroundColor(DS.TextColor.secondary)
                        if let eta = etaText {
                            Text("·")
                                .foregroundColor(DS.TextColor.tertiary)
                            Text(eta)
                                .font(DS.Font.monoSmall)
                                .foregroundColor(DS.TextColor.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(Color.black.opacity(DS.Opacity.primary))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(DS.Semantic.info.opacity(DS.Opacity.tertiary), lineWidth: 0.5)
                    )
            )
            .fixedSize()
            .opacity(opacity)
            .accessibilityLabel("\(state.displayName), O₂ \(Int(oxygenLevel * 100))%")
            .onAppear {
                withAnimation(.easeIn(duration: 0.15)) {
                    opacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
