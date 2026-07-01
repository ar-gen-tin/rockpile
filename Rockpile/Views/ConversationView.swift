import SwiftUI

/// Chat-style conversation view — displays parsed Claude Code JSONL messages.
struct ConversationView: View {
    let messages: [ConversationMessage]

    var body: some View {
        if messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ConversationMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(DS.Font.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Semantic.info.opacity(0.4))
                    )
            }

        case .assistant:
            HStack {
                Text(message.content)
                    .font(DS.Font.body)
                    .foregroundColor(DS.TextColor.primary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Surface.raised)
                    )
                Spacer(minLength: 40)
            }

        case .tool:
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 9))
                    .foregroundColor(DS.Semantic.toolCall)
                Text(message.toolName ?? "tool")
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.Semantic.toolCall)
                if let content = message.content.isEmpty ? nil : message.content,
                   content != message.toolName {
                    Text(content)
                        .font(DS.Font.monoSmall)
                        .foregroundColor(DS.TextColor.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Semantic.toolCall.opacity(DS.Opacity.ghost))
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 20))
                .foregroundColor(DS.TextColor.muted)
            Text("Waiting for conversation…")
                .font(DS.Font.body)
                .foregroundColor(DS.TextColor.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, DS.Space.xl)
    }
}
