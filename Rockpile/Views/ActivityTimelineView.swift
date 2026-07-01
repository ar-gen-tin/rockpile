import SwiftUI

/// Timeline view — chronological event stream grouped by session.
struct ActivityTimelineView: View {
    let sessionStore: SessionStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                let activeSessions = sessionStore.sortedSessions
                ForEach(activeSessions) { session in
                    timeAnchor(session.lastEventTime)
                    sessionBlock(session)
                }

                let history = SessionHistory.shared.records
                ForEach(history.prefix(20)) { record in
                    timeAnchor(record.startTime)
                    historyBlock(record)
                }

                if activeSessions.isEmpty && history.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
        }
    }

    // MARK: - Time Anchor

    @ViewBuilder
    private func timeAnchor(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            Text(formatTime(date))
                .font(DS.Font.caption)
                .foregroundColor(DS.TextColor.muted)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Active Session Block

    @ViewBuilder
    private func sessionBlock(_ session: SessionData) -> some View {
        let accentColor = session.creatureType == .hermitCrab
            ? DS.Semantic.success.opacity(0.3)
            : DS.Semantic.warning.opacity(0.25)

        VStack(alignment: .leading, spacing: 3) {
            // Session header
            HStack(spacing: 5) {
                Text(session.creatureType == .hermitCrab ? "🐚" : "🦞")
                    .font(.system(size: 11))
                Text(projectName(session.cwd))
                    .font(DS.Font.mono)
                    .foregroundColor(DS.TextColor.secondary)
            }

            ForEach(session.activities.suffix(8), id: \.id) { activity in
                activityRow(activity)
            }

            if session.tokenTracker.sessionTotalTokens > 0 {
                statsRow(
                    duration: formatDuration(session.activities.first?.timestamp ?? session.lastEventTime),
                    input: session.tokenTracker.sessionInputTokens,
                    output: session.tokenTracker.sessionOutputTokens
                )
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 2)
        }
    }

    // MARK: - History Record Block

    @ViewBuilder
    private func historyBlock(_ record: SessionRecord) -> some View {
        let isLocal = (record.creatureType ?? .crawfish) == .hermitCrab
        let accentColor = isLocal
            ? DS.Semantic.success.opacity(0.18)
            : DS.Semantic.warning.opacity(0.15)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(isLocal ? "🐚" : "🦞")
                    .font(.system(size: 11))
                Text(record.sessionId.prefix(8).description)
                    .font(DS.Font.mono)
                    .foregroundColor(DS.TextColor.tertiary)
            }

            if !record.toolNames.isEmpty {
                let tools = record.toolNames.prefix(3).joined(separator: " · ")
                let extra = record.toolCallCount > 3 ? " +\(record.toolCallCount - 3)" : ""
                Text("🔨 \(tools)\(extra)")
                    .font(DS.Font.mono)
                    .foregroundColor(DS.TextColor.muted)
            }

            statsRow(
                duration: record.durationText,
                input: record.inputTokens ?? 0,
                output: record.outputTokens ?? 0
            )
        }
        .padding(.leading, 12)
        .opacity(0.7)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 2)
        }
    }

    // MARK: - Activity Row

    @ViewBuilder
    private func activityRow(_ activity: ActivityItem) -> some View {
        HStack(spacing: 5) {
            Text(activityIcon(activity.type))
                .font(.system(size: 10))
            Text(activity.detail)
                .font(DS.Font.mono)
                .foregroundColor(activityColor(activity.type))
                .lineLimit(1)
        }
    }

    // MARK: - Stats Row

    @ViewBuilder
    private func statsRow(duration: String, input: Int, output: Int) -> some View {
        HStack(spacing: 8) {
            Text(duration)
                .font(DS.Font.monoBold)
                .foregroundColor(DS.TextColor.secondary)
            if input > 0 || output > 0 {
                Text("\(TokenTracker.formatTokens(input)) in · \(TokenTracker.formatTokens(output)) out")
                    .font(DS.Font.caption)
                    .foregroundColor(DS.TextColor.muted)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            Text(L10n.s("dash.waiting"))
                .font(DS.Font.subhead)
                .foregroundColor(DS.TextColor.secondary)
            Text(L10n.s("dash.waitingDesc"))
                .font(DS.Font.body)
                .foregroundColor(DS.TextColor.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }

    // MARK: - Helpers

    private func activityIcon(_ type: ActivityItem.ActivityType) -> String {
        switch type {
        case .thinking:   return "🧠"
        case .toolCall:   return "🔨"
        case .toolResult: return "✅"
        case .error:      return "⚠️"
        case .message:    return "💬"
        case .completion: return "✅"
        }
    }

    private func activityColor(_ type: ActivityItem.ActivityType) -> Color {
        switch type {
        case .thinking:   return DS.TextColor.tertiary
        case .toolCall:   return DS.TextColor.secondary
        case .toolResult: return DS.Semantic.success
        case .error:      return DS.Semantic.danger
        case .message:    return DS.TextColor.primary
        case .completion: return DS.Semantic.success
        }
    }

    private func projectName(_ cwd: String) -> String {
        guard !cwd.isEmpty else { return "session" }
        return "~/\((cwd as NSString).lastPathComponent)"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ startTime: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(startTime))
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 { return "\(mins)m\(secs)s" }
        return "\(mins / 60)h\(mins % 60)m"
    }
}
