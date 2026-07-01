import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ConversationParser")

/// Incrementally parses Claude Code JSONL conversation files.
///
/// Watches `~/.claude/projects/<dir>/<sessionId>.jsonl` and only reads new content
/// since the last parse. Uses 500ms debouncing.
actor ConversationParser {
    static let shared = ConversationParser()

    /// Parsed messages per session — accessed from MainActor
    private var sessionMessages: [String: [ConversationMessage]] = [:]

    /// File offsets for incremental reading
    private var fileOffsets: [String: UInt64] = [:]

    /// Debounce tracking
    private var pendingSyncs: Set<String> = []

    private let maxMessages = 50

    private init() {}

    /// Get messages for a session (thread-safe copy)
    func messages(for sessionId: String) -> [ConversationMessage] {
        sessionMessages[sessionId] ?? []
    }

    /// Trigger an incremental sync for a session.
    /// Called from StateMachine after relevant events.
    func syncSession(sessionId: String, cwd: String) {
        guard !sessionId.isEmpty, !cwd.isEmpty else { return }

        // Debounce: skip if already pending
        guard !pendingSyncs.contains(sessionId) else { return }
        pendingSyncs.insert(sessionId)

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            pendingSyncs.remove(sessionId)
            await parseIncremental(sessionId: sessionId, cwd: cwd)
        }
    }

    // MARK: - Parsing

    private func parseIncremental(sessionId: String, cwd: String) async {
        // Find JSONL file
        guard let filePath = findJSONLFile(sessionId: sessionId, cwd: cwd) else { return }

        let fileURL = URL(fileURLWithPath: filePath)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        // Seek to last known offset
        let offset = fileOffsets[sessionId] ?? 0
        try? handle.seek(toOffset: offset)

        guard let newData = try? handle.readToEnd(), !newData.isEmpty else { return }

        // Update offset
        fileOffsets[sessionId] = offset + UInt64(newData.count)

        // Parse new lines
        guard let text = String(data: newData, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

        var messages = sessionMessages[sessionId] ?? []

        var parseErrors = 0
        for (idx, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                parseErrors += 1
                if parseErrors <= 3 {
                    logger.warning("JSONL parse error at line \(idx): \(line.prefix(80), privacy: .public)")
                }
                continue
            }

            if let msg = parseMessage(from: json) {
                messages.append(msg)
            }
        }

        // Trim to max
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }

        sessionMessages[sessionId] = messages
    }

    private func parseMessage(from json: [String: Any]) -> ConversationMessage? {
        let type = json["type"] as? String ?? ""

        // Handle different JSONL formats
        switch type {
        case "human", "user":
            let content = extractContent(from: json)
            guard !content.isEmpty else { return nil }
            return ConversationMessage(role: .user, content: content)

        case "assistant":
            let content = extractContent(from: json)
            guard !content.isEmpty else { return nil }
            return ConversationMessage(role: .assistant, content: content)

        case "tool_use", "tool_call":
            let toolName = json["name"] as? String ?? json["tool_name"] as? String ?? "tool"
            return ConversationMessage(role: .tool, content: toolName, toolName: toolName)

        case "tool_result":
            let toolName = json["tool_name"] as? String ?? "tool"
            let content = extractContent(from: json)
            let summary = content.isEmpty ? "\(toolName) done" : content
            return ConversationMessage(role: .tool, content: summary, toolName: toolName)

        default:
            // Try role-based parsing
            if let role = json["role"] as? String {
                let content = extractContent(from: json)
                guard !content.isEmpty else { return nil }
                switch role {
                case "user": return ConversationMessage(role: .user, content: content)
                case "assistant": return ConversationMessage(role: .assistant, content: content)
                default: return nil
                }
            }
            return nil
        }
    }

    private func extractContent(from json: [String: Any]) -> String {
        // Direct string content
        if let text = json["content"] as? String {
            return text
        }
        // Array content (Claude API format)
        if let blocks = json["content"] as? [[String: Any]] {
            return blocks.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                if block["type"] as? String == "tool_use" {
                    return "[tool: \(block["name"] as? String ?? "?")]"
                }
                return nil
            }.joined(separator: " ")
        }
        // Message field
        if let msg = json["message"] as? String {
            return msg
        }
        // Prompt field
        if let prompt = json["prompt"] as? String {
            return prompt
        }
        return ""
    }

    private func findJSONLFile(sessionId: String, cwd: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        // Try direct session file
        let directPath = projectsDir
            .appendingPathComponent(sanitizePath(cwd))
            .appendingPathComponent("\(sessionId).jsonl")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath.path
        }

        // Try finding in any project dir
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil) else {
            return nil
        }

        for dir in projectDirs {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        return nil
    }

    /// Sanitize cwd to match Claude's project directory naming
    private func sanitizePath(_ path: String) -> String {
        // Claude uses the full path with slashes replaced
        path.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
