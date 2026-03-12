import SwiftUI

/// Token 消耗概览卡片 — 双生物消耗全局一览
///
/// 布局 (~48pt 高，两栏)：
/// ┌──────────────────────┬──────────────────────┐
/// │ 🐚 2.1K/m ↑  ~1.8h  │ 🦞 850/m →  ~4.2h   │
/// │ 日进度 42%    正常    │ 日进度 23%    偏慢    │
/// └──────────────────────┴──────────────────────┘
///
/// 仅当任一 tracker 有活跃消耗数据 (burnRate > 0) 时显示。
struct TokenConsumptionCard: View {
    let localTracker: TokenTracker
    let remoteTracker: TokenTracker

    var body: some View {
        HStack(spacing: 0) {
            creatureColumn(
                icon: "🐚",
                tracker: localTracker,
                accent: DS.Semantic.localAccent
            )

            Rectangle()
                .fill(DS.Surface.divider)
                .frame(width: 1)
                .padding(.vertical, DS.Space.xs)

            creatureColumn(
                icon: "🦞",
                tracker: remoteTracker,
                accent: DS.Semantic.remoteAccent
            )
        }
        .padding(.vertical, DS.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Compact.cardRadius)
                .fill(DS.Surface.raised)
        )
    }

    // MARK: - Single Creature Column

    @ViewBuilder
    private func creatureColumn(icon: String, tracker: TokenTracker, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            // Row 1: icon + burnRate + velocity + ETA
            HStack(spacing: DS.Space.xs) {
                Text(icon)
                    .font(.system(size: 9))

                if tracker.burnRate > 0 {
                    Text("\(tracker.burnRateText)")
                        .font(DS.Font.monoSmall)
                        .foregroundColor(paceColor(tracker, accent: accent))

                    Text(tracker.velocityArrow)
                        .font(DS.Font.monoSmall)
                        .foregroundColor(DS.TextColor.tertiary)

                    Spacer()

                    if let eta = tracker.etaText {
                        Text(eta)
                            .font(DS.Font.monoSmall)
                            .foregroundColor(etaColor(tracker))
                    }
                } else {
                    Text("---")
                        .font(DS.Font.monoSmall)
                        .foregroundColor(DS.TextColor.muted)
                    Spacer()
                }
            }

            // Row 2: daily progress + pace label
            HStack(spacing: DS.Space.xs) {
                let progress = dailyProgress(tracker)
                Text("\(L10n.s("dash.dailyProgress")) \(progress)%")
                    .font(DS.Font.monoTiny)
                    .foregroundColor(DS.TextColor.tertiary)

                Spacer()

                Text(paceLabel(tracker))
                    .font(DS.Font.monoTiny)
                    .foregroundColor(paceColor(tracker, accent: accent))
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// 日进度百分比: effectiveDailyUsed / tankCapacity
    private func dailyProgress(_ tracker: TokenTracker) -> Int {
        let cap = tracker.tankCapacityForDisplay
        guard cap > 0 else { return 0 }
        return min(100, Int(Double(tracker.effectiveDailyUsed) / Double(cap) * 100))
    }

    /// 配速状态标签
    private func paceLabel(_ tracker: TokenTracker) -> String {
        switch tracker.paceStatus {
        case .ahead:   return L10n.s("dash.pace.ahead")
        case .onTrack: return L10n.s("dash.pace.onTrack")
        case .behind:  return L10n.s("dash.pace.behind")
        case .idle:    return L10n.s("dash.pace.idle")
        }
    }

    /// 配速颜色
    private func paceColor(_ tracker: TokenTracker, accent: Color) -> Color {
        switch tracker.paceStatus {
        case .ahead:   return DS.Semantic.warning
        case .onTrack: return accent
        case .behind:  return DS.Semantic.success
        case .idle:    return DS.TextColor.tertiary
        }
    }

    /// ETA 颜色
    private func etaColor(_ tracker: TokenTracker) -> Color {
        guard let eta = tracker.etaMinutes else { return DS.TextColor.tertiary }
        if eta < 30 { return DS.Semantic.danger }
        if eta < 120 { return DS.Semantic.warning }
        return DS.TextColor.tertiary
    }
}
