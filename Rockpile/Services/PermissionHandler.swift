import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "PermissionHandler")

/// Handles Claude Code tool permission requests.
///
/// Flow: Hook script sends PermissionRequest → SocketServer → StateMachine → PermissionHandler
/// User clicks Allow/Deny → PermissionHandler writes response to /tmp/rockpile-permission-<id>.json
/// Hook script polls for this file and returns the decision to Claude Code.
@MainActor
@Observable
final class PermissionHandler {
    static let shared = PermissionHandler()

    struct PermissionRequest: Identifiable {
        let id: String  // tool_use_id
        let toolName: String
        let inputSummary: String
        let sessionId: String
        let receivedAt: Date
        var timeoutTask: Task<Void, Never>?
    }

    enum Decision: String {
        case allow
        case deny
    }

    private(set) var pendingPermissions: [PermissionRequest] = []

    /// Timeout duration (5 minutes)
    private let timeoutDuration: TimeInterval = 300

    private init() {
        cleanupStaleFiles()
    }

    /// Remove stale permission response files from /tmp on launch
    private func cleanupStaleFiles() {
        let fm = FileManager.default
        let tmpDir = "/tmp"
        guard let files = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        let staleThreshold: TimeInterval = 600  // 10 minutes
        let now = Date()
        for file in files where file.hasPrefix("rockpile-permission-") && file.hasSuffix(".json") {
            let path = "\(tmpDir)/\(file)"
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > staleThreshold else { continue }
            try? fm.removeItem(atPath: path)
            logger.info("Cleaned stale permission file: \(file, privacy: .public)")
        }
    }

    /// Add a new permission request
    func addRequest(toolUseId: String, toolName: String, toolInput: [String: String]?, sessionId: String) {
        // Avoid duplicates
        guard !pendingPermissions.contains(where: { $0.id == toolUseId }) else { return }

        let inputSummary = formatInputSummary(toolInput)

        var request = PermissionRequest(
            id: toolUseId,
            toolName: toolName,
            inputSummary: inputSummary,
            sessionId: sessionId,
            receivedAt: Date()
        )

        // Auto-deny after timeout
        request.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.timeoutDuration ?? 300))
            guard !Task.isCancelled else { return }
            self?.decide(toolUseId, .deny)
        }

        pendingPermissions.append(request)
        logger.info("Permission request: \(toolName, privacy: .public) [\(toolUseId, privacy: .public)]")
    }

    /// User decision: allow or deny
    func decide(_ toolUseId: String, _ decision: Decision) {
        guard let index = pendingPermissions.firstIndex(where: { $0.id == toolUseId }) else { return }

        let request = pendingPermissions[index]
        request.timeoutTask?.cancel()
        pendingPermissions.remove(at: index)

        writeResponseFile(toolUseId: toolUseId, decision: decision)
        logger.info("Permission \(decision.rawValue, privacy: .public): \(request.toolName, privacy: .public)")
    }

    /// Cancel a pending permission (e.g. when PostToolUse arrives, meaning user already responded in terminal)
    func cancelIfPending(_ toolUseId: String) {
        guard let index = pendingPermissions.firstIndex(where: { $0.id == toolUseId }) else { return }
        pendingPermissions[index].timeoutTask?.cancel()
        pendingPermissions.remove(at: index)
        logger.info("Permission cancelled (handled elsewhere): \(toolUseId, privacy: .public)")
    }

    /// Cancel all pending for a session
    func cancelAll(for sessionId: String) {
        let matching = pendingPermissions.filter { $0.sessionId == sessionId }
        for request in matching {
            request.timeoutTask?.cancel()
        }
        pendingPermissions.removeAll { $0.sessionId == sessionId }
    }

    /// Time remaining for a request
    func timeRemaining(for request: PermissionRequest) -> TimeInterval {
        max(0, timeoutDuration - Date().timeIntervalSince(request.receivedAt))
    }

    // MARK: - Private

    private func writeResponseFile(toolUseId: String, decision: Decision) {
        let filePath = "/tmp/rockpile-permission-\(toolUseId).json"

        let response: [String: Any] = [
            "decision": decision.rawValue,
            "tool_use_id": toolUseId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: response) else {
            logger.error("Failed to serialize permission response")
            return
        }

        // O_CREAT | O_EXCL: fail if file already exists (anti-TOCTOU pre-creation attack)
        let fd = open(filePath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if fd < 0 {
            // File already exists — possible stale file. Remove and retry once.
            logger.warning("Permission file already exists, removing stale: \(filePath, privacy: .public)")
            unlink(filePath)
            let fd2 = open(filePath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd2 >= 0 else {
                logger.error("Failed to create permission response file after retry")
                return
            }
            data.withUnsafeBytes { buf in
                _ = write(fd2, buf.baseAddress!, buf.count)
            }
            close(fd2)
            return
        }
        data.withUnsafeBytes { buf in
            _ = write(fd, buf.baseAddress!, buf.count)
        }
        close(fd)
        logger.info("Wrote permission response to \(filePath, privacy: .public)")
    }

    private func formatInputSummary(_ input: [String: String]?) -> String {
        guard let input = input, !input.isEmpty else { return "" }
        return input.map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
            .prefix(150)
            .description
    }
}
