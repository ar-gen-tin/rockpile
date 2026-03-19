import SwiftUI

/// 服务状态条 — 紧凑 HStack 显示各 AI 服务健康状态
///
/// 彩色圆点 + 服务名，点击展开组件详情。
/// 集成到 dashboardView 的 O₂ bar 下方。
struct ServiceStatusBarView: View {
    @State private var expandedServiceId: String?

    var body: some View {
        let monitor = ServiceStatusMonitor.shared
        let results = monitor.sortedResults

        if !results.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    ForEach(results) { result in
                        statusDot(result)
                    }
                    Spacer()
                    if monitor.isRefreshing {
                        Text(L10n.s("svcStatus.checking"))
                            .font(DS.Font.monoTiny)
                            .foregroundColor(DS.TextColor.muted)
                    }
                }

                // Expanded component detail
                if let expandedId = expandedServiceId,
                   let result = monitor.results[expandedId],
                   !result.components.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        ForEach(result.components, id: \.name) { comp in
                            HStack(spacing: DS.Space.xs) {
                                Circle()
                                    .fill(healthColor(comp.status))
                                    .frame(width: 4, height: 4)
                                Text(comp.name)
                                    .font(DS.Font.monoTiny)
                                    .foregroundColor(DS.TextColor.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, DS.Space.xs)
                    .transition(.opacity)
                }
            }
        }
    }

    private func statusDot(_ result: ServiceStatusResult) -> some View {
        Button {
            withAnimation(.easeInOut(duration: DS.Timing.stateChange)) {
                if expandedServiceId == result.id {
                    expandedServiceId = nil
                } else {
                    expandedServiceId = result.id
                }
            }
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Circle()
                    .fill(healthColor(result.status))
                    .frame(width: 6, height: 6)
                Text(result.service.name)
                    .font(DS.Font.monoTiny)
                    .foregroundColor(DS.TextColor.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(expandedServiceId == result.id ? DS.Surface.raised : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func healthColor(_ status: HealthStatus) -> Color {
        switch status {
        case .operational:  return DS.Semantic.success
        case .degraded:     return DS.Semantic.warning
        case .majorOutage:  return DS.Semantic.danger
        case .unknown:      return Color.gray
        }
    }
}
