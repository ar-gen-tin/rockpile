import SwiftUI

/// Session list — shows all active sessions when count > 1.
/// Each row: status dot + project name (cwd basename) + last activity time + delete button.
struct SessionListView: View {
    let sessions: [SessionData]
    let selectedSessionId: String?
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DS.sectionLabel(L10n.s("dash.activity") + " (\(sessions.count))")

            ForEach(sortedSessions) { session in
                sessionRow(session)
            }
        }
    }

    /// Sort: working/thinking > idle > sleeping
    private var sortedSessions: [SessionData] {
        sessions.sorted { a, b in
            a.state.task.sortPriority > b.state.task.sortPriority
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionData) -> some View {
        let isSelected = session.id == selectedSessionId
        HStack(spacing: DS.Space.xs) {
            // Status color dot
            Circle()
                .fill(statusColor(for: session.state.task))
                .frame(width: 6, height: 6)

            // Creature icon
            Text(session.creatureType == .hermitCrab ? "🐚" : "🦞")
                .font(DS.Font.tiny)

            // Project name (cwd basename)
            Text(projectName(from: session.cwd))
                .font(DS.Font.mono)
                .foregroundColor(isSelected ? DS.TextColor.primary : DS.TextColor.secondary)
                .lineLimit(1)

            Spacer()

            // Last activity relative time
            Text(relativeTime(since: session.lastEventTime))
                .font(DS.Font.monoSmall)
                .foregroundColor(DS.TextColor.tertiary)

            // Remove button
            Button {
                onRemove(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DS.TextColor.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(isSelected ? DS.Surface.raised : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(session.id)
        }
    }

    private func statusColor(for task: ClawTask) -> Color {
        switch task {
        case .working, .thinking, .compacting: return DS.Semantic.success
        case .idle, .waiting:                  return DS.Semantic.info
        case .sleeping:                        return DS.TextColor.muted
        case .error:                           return DS.Semantic.danger
        }
    }

    private func projectName(from cwd: String) -> String {
        guard !cwd.isEmpty else { return "session" }
        return (cwd as NSString).lastPathComponent
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

// MARK: - ClawTask Sort Priority

extension ClawTask {
    var sortPriority: Int {
        switch self {
        case .working:    return 5
        case .thinking:   return 4
        case .compacting: return 3
        case .idle:       return 2
        case .waiting:    return 1
        case .sleeping:   return 0
        case .error:      return 3
        }
    }
}
