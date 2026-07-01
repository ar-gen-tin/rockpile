import SwiftUI

/// 展开面板底部输入框 — 极简风格
struct SpotlightInputView: View {
    let onSend: (String) -> Void

    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            HStack(spacing: DS.Space.sm) {
                Text(">")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(isFocused ? DS.Semantic.accent : DS.TextColor.muted)

                TextField("", text: $inputText, prompt: Text(L10n.s("input.placeholder"))
                    .foregroundColor(DS.TextColor.muted))
                    .textFieldStyle(.plain)
                    .font(DS.Font.monoBody)
                    .foregroundColor(DS.TextColor.primary)
                    .focused($isFocused)
                    .onSubmit {
                        sendMessage()
                    }
                    .onKeyPress(.escape) {
                        isFocused = false
                        inputText = ""
                        NotchPanel.returnFocusToPreviousApp()
                        return .handled
                    }

                if !inputText.isEmpty {
                    Button(action: sendMessage) {
                        Text("↵")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                            .background(DS.Semantic.accent)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.s("input.send"))
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 8)

            // Status feedback
            feedbackBar
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var feedbackBar: some View {
        let result = CommandSender.shared.lastResult
        switch result {
        case .idle, .sending:
            EmptyView()
        case .sent(let method):
            feedbackText("\(L10n.s("input.sent")) (\(method))", color: DS.Semantic.success)
        case .queued:
            feedbackText(L10n.s("input.waitingConnection"), color: DS.Semantic.warning)
        case .noSession:
            feedbackText(L10n.s("input.noSession"), color: DS.Semantic.warning)
        case .error(let msg):
            feedbackText(msg, color: DS.Semantic.danger)
        }
    }

    @ViewBuilder
    private func feedbackText(_ text: String, color: Color) -> some View {
        HStack {
            Text(text)
                .font(DS.Font.caption)
                .foregroundColor(color)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.xxs)
        .frame(height: 20)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text)
        inputText = ""
        isFocused = false
        NotchPanel.returnFocusToPreviousApp()
    }
}
