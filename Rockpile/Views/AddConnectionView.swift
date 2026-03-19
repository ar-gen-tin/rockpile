import SwiftUI

/// 添加自定义连接 — Sheet 形式
///
/// URL 输入 + 自动检测 badge + 名称 + 保存/取消
struct AddConnectionView: View {
    @Binding var connections: [CustomConnection]
    @Binding var isPresented: Bool

    @State private var url = ""
    @State private var name = ""
    @State private var detectedType: ConnectionType = .unknown
    @State private var isDetecting = false
    @State private var detectTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(L10n.s("conn.add"))
                .font(DS.Font.title)
                .foregroundColor(DS.TextColor.primary)

            // URL field
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(L10n.s("conn.url"))
                    .font(DS.Font.secondary)
                    .foregroundColor(DS.TextColor.secondary)
                HStack(spacing: DS.Space.xs) {
                    TextField("ws://host:port", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(DS.Font.mono)
                        .onChange(of: url) {
                            debounceDetect()
                        }
                    if isDetecting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if detectedType != .unknown {
                        typeBadge(detectedType)
                    }
                }
            }

            // Name field
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(L10n.s("conn.name"))
                    .font(DS.Font.secondary)
                    .foregroundColor(DS.TextColor.secondary)
                TextField("My Service", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Font.mono)
            }

            // URL validation
            if !url.isEmpty && !ConnectionDetector.isValidURL(url) {
                Text(L10n.s("conn.invalidURL"))
                    .font(DS.Font.secondary)
                    .foregroundColor(DS.Semantic.danger)
            }

            Spacer()

            // Actions
            HStack {
                Button(L10n.s("conn.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.TextColor.secondary)

                Spacer()

                Button(L10n.s("conn.save")) {
                    let connection = CustomConnection(
                        name: name.isEmpty ? url : name,
                        url: url,
                        type: detectedType
                    )
                    connections.append(connection)
                    CustomConnection.saveAll(connections)
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Semantic.accent)
                .disabled(url.isEmpty || !ConnectionDetector.isValidURL(url))
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 320, height: 280)
    }

    private func typeBadge(_ type: ConnectionType) -> some View {
        Text(type.rawValue)
            .font(DS.Font.monoTiny)
            .foregroundColor(DS.Semantic.accent)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Semantic.accent.opacity(DS.Opacity.ghost))
            )
    }

    private func debounceDetect() {
        detectTask?.cancel()
        detectTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, ConnectionDetector.isValidURL(url) else { return }
            isDetecting = true
            detectedType = await ConnectionDetector.detect(url: url)
            isDetecting = false
        }
    }
}
