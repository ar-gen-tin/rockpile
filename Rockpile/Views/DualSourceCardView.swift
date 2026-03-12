import SwiftUI

/// 双源合并信息行 — 一排显示两只生物的提供商 + 状态
///
/// 布局: 🐚 [Claude 订阅·日配额] ●空闲 ▸   🦞 [xAI·按量] ●工作中 ▸
struct DualSourceInfoRow: View {
    let localSession: SessionData?
    let remoteSession: SessionData?
    let localSessionCount: Int
    let remoteSessionCount: Int
    @Binding var localExpanded: Bool
    @Binding var remoteExpanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: 寄居蟹 ──
            creatureInfoCell(
                creature: .hermitCrab,
                session: localSession,
                sessionCount: localSessionCount,
                isExpanded: $localExpanded
            )

            // 分隔线
            Rectangle()
                .fill(DS.Surface.divider)
                .frame(width: 1)
                .padding(.vertical, DS.Space.xs)

            // ── Right: 小龙虾 ──
            creatureInfoCell(
                creature: .crawfish,
                session: remoteSession,
                sessionCount: remoteSessionCount,
                isExpanded: $remoteExpanded
            )
        }
        .padding(.vertical, DS.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Compact.cardRadius)
                .fill(DS.Surface.raised)
        )
    }

    // MARK: - Cell

    @ViewBuilder
    private func creatureInfoCell(
        creature: CreatureType,
        session: SessionData?,
        sessionCount: Int,
        isExpanded: Binding<Bool>
    ) -> some View {
        let accent = creature == .hermitCrab ? DS.Semantic.localAccent : DS.Semantic.remoteAccent
        let provider = creature == .hermitCrab
            ? AIProviderDetector.detectLocalProvider()
            : AIProviderDetector.detectRemoteProvider()

        HStack(spacing: DS.Space.xs) {
            Text(creature.icon)
                .font(DS.Font.secondary)

            // Provider tag
            if provider != .unknown {
                Text(providerLabel(provider, creature: creature))
                    .font(DS.Font.monoSmall)
                    .foregroundColor(accent.opacity(DS.Opacity.secondary))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(DS.Opacity.ghost))
                    )
                    .lineLimit(1)
            }

            // State dot + name
            if let session {
                Circle()
                    .fill(session.state.task.statusColor)
                    .frame(width: 5, height: 5)
                Text(session.state.displayName)
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.secondary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(L10n.s("state.sleeping"))
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.muted)
            }

            // API indicator
            let isAPI = creature == .hermitCrab ? AppSettings.localUsageAPIEnabled : AppSettings.remoteUsageAPIEnabled
            if isAPI {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 7))
                    .foregroundColor(apiColor(creature))
            }

            Spacer(minLength: 2)

            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.tertiary)
            }

            // 只在有活动 session 时显示展开箭头
            if session != nil {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(DS.TextColor.muted)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .contentShape(Rectangle())
        .onTapGesture {
            guard session != nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func providerLabel(_ provider: AIProvider, creature: CreatureType) -> String {
        let name = provider.displayName
        let billing = provider.billingLabel
        if billing.isEmpty {
            return creature == .hermitCrab ? L10n.s("creature.local") : L10n.s("creature.remote")
        }
        return "\(name) · \(billing)"
    }

    private func apiColor(_ creature: CreatureType) -> Color {
        let svc = UsageQueryService.shared
        let querying = creature == .hermitCrab ? svc.isQueryingLocal : svc.isQueryingRemote
        let error = creature == .hermitCrab ? svc.localError : svc.remoteError
        if querying { return .yellow }
        if error != nil { return DS.Semantic.danger }
        return DS.Semantic.success
    }
}

/// 展开的活动日志区域 — 从 DualSourceCardView 拆出
struct DualSourceActivitySection: View {
    let session: SessionData
    let creatureType: CreatureType

    private var accent: Color {
        creatureType == .hermitCrab ? DS.Semantic.localAccent : DS.Semantic.remoteAccent
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Text(creatureType.icon)
                    .font(DS.Font.secondary)
                Text(L10n.s("dash.activity"))
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.secondary)
            }

            ForEach(session.activities.suffix(5).reversed()) { item in
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: activityIcon(for: item.type))
                        .font(DS.Font.tiny)
                        .foregroundColor(activityColor(for: item.type))
                        .frame(width: 12)
                    Text(item.detail)
                        .font(DS.Font.secondary)
                        .foregroundColor(DS.TextColor.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(DS.Font.monoSmall)
                        .foregroundColor(DS.TextColor.muted)
                }
            }
        }
        .padding(DS.Compact.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DS.Compact.cardRadius)
                .fill(DS.Surface.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Compact.cardRadius)
                        .strokeBorder(accent.opacity(DS.Opacity.muted), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func activityIcon(for type: ActivityItem.ActivityType) -> String {
        switch type {
        case .thinking:   return "brain"
        case .toolCall:   return "wrench"
        case .toolResult: return "checkmark.circle"
        case .error:      return "exclamationmark.triangle"
        case .message:    return "bubble.left"
        case .completion: return "flag.checkered"
        }
    }

    private func activityColor(for type: ActivityItem.ActivityType) -> Color {
        switch type {
        case .thinking:   return DS.Semantic.thinking
        case .toolCall:   return DS.Semantic.toolCall
        case .toolResult: return DS.Semantic.success
        case .error:      return DS.Semantic.danger
        case .message:    return DS.Semantic.info
        case .completion: return DS.Semantic.success
        }
    }
}
