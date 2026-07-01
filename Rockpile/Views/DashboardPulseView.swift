import SwiftUI

/// 仪表脉冲条 — 足迹标题栏右侧的 Gateway 健康摘要
///
/// Gateway 已连接时显示：🟢 3会话 · grok-4
/// Gateway 未连接时回退：近 N 次
struct DashboardPulseView: View {
    let snapshot: GatewaySnapshot?
    let historyCount: Int
    let isLoading: Bool

    var body: some View {
        if let snap = snapshot {
            HStack(spacing: DS.Space.xs) {
                Circle()
                    .fill(snap.healthColor)
                    .frame(width: 5, height: 5)
                Text(snap.summaryText)
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.tertiary)
            }
        } else if isLoading {
            HStack(spacing: DS.Space.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text("同步中...")
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.muted)
            }
        } else {
            Text("近 \(historyCount) 次")
                .font(DS.Font.secondary)
                .foregroundColor(DS.TextColor.tertiary)
        }
    }
}
