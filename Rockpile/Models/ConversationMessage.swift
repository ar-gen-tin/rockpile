import Foundation

/// A single message from a Claude Code JSONL conversation log.
struct ConversationMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let toolName: String?
    let timestamp: Date

    enum Role: String, Sendable {
        case user
        case assistant
        case tool
    }

    init(role: Role, content: String, toolName: String? = nil, timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = String(content.prefix(200))
        self.toolName = toolName
        self.timestamp = timestamp
    }
}
