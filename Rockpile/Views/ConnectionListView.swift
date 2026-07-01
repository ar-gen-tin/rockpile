import SwiftUI

/// 已保存连接列表 — enable/disable toggle + 删除
struct ConnectionListView: View {
    @Binding var connections: [CustomConnection]

    var body: some View {
        if connections.isEmpty {
            Text(L10n.s("conn.empty"))
                .font(DS.Font.secondary)
                .foregroundColor(DS.TextColor.muted)
        } else {
            ForEach(connections) { conn in
                HStack(spacing: DS.Space.xs) {
                    Toggle("", isOn: Binding(
                        get: { conn.isEnabled },
                        set: { newValue in
                            if let idx = connections.firstIndex(where: { $0.id == conn.id }) {
                                connections[idx].isEnabled = newValue
                                CustomConnection.saveAll(connections)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 1) {
                        Text(conn.name)
                            .font(DS.Font.secondary)
                            .foregroundColor(conn.isEnabled ? DS.TextColor.primary : DS.TextColor.muted)
                            .lineLimit(1)
                        Text(conn.url)
                            .font(DS.Font.monoTiny)
                            .foregroundColor(DS.TextColor.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(conn.type.rawValue)
                        .font(DS.Font.monoTiny)
                        .foregroundColor(DS.TextColor.muted)

                    Button {
                        connections.removeAll { $0.id == conn.id }
                        CustomConnection.saveAll(connections)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(DS.TextColor.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
