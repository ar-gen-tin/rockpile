import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "EventLogger")

/// 持久化文件日志器 — 用于调试和诊断
///
/// 日志写入 ~/Library/Logs/Rockpile/rockpile.log
/// 超过 2MB 自动轮转为 rockpile.log.1
///
/// 日志分类（用 emoji 前缀快速定位）：
/// - 📥 原始数据接收
/// - 📨 解析后的事件
/// - 🦞+/🦞- 会话创建/移除
/// - 🔄 状态变化
/// - 🫧 O₂ 区间变化
/// - 🔌 网络连接
/// - ⚠️ 解析失败
/// - 🧹 过期清理
/// - ⚙️ 配置变更
/// - 💓 心跳
/// - 📋 足迹保存
@MainActor
final class EventLogger {
    static let shared = EventLogger()

    private let logDir: URL
    private let logFile: URL
    private let dateFormatter: DateFormatter
    private let maxLogSize: Int = 2 * 1024 * 1024 // 2MB, auto-rotate

    /// Persistent file handle — avoids open/seek/close per log line
    private var fileHandle: FileHandle?
    private var flushTimer: Timer?

    /// 心跳计时器 — 每 5 分钟记录运行状态
    private var heartbeatTimer: Timer?

    /// 轮转中缓冲 — 防止 rotateIfNeeded 执行期间丢失日志
    private var isRotating = false
    private var rotationBuffer: [String] = []

    /// 启动时间
    private let launchTime = Date()

    /// 事件计数器（用于心跳摘要）
    private var eventCount: Int = 0

    // Note: No deinit needed — singleton (`shared`) is never deallocated.
    // Adding deinit would require `nonisolated(unsafe)` on timers/fileHandle
    // due to Swift 6 MainActor isolation rules.

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDir = home.appendingPathComponent("Library/Logs/Rockpile")
        logFile = logDir.appendingPathComponent("rockpile.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Ensure log directory exists
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        openFileHandle()

        logStartupDiagnostics()
        startHeartbeat()

        // Flush buffered writes every 2 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fileHandle?.synchronizeFile() }
        }
    }

    private func openFileHandle() {
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()
    }

    // MARK: - Startup Diagnostics

    /// 启动时记录系统环境信息，帮助定位环境相关 BUG
    private func logStartupDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let role = AppSettings.setupRole == .none ? "未配置" : AppSettings.setupRole.rawValue
        let o2Mode = AppSettings.oxygenMode == "claude" ? "Claude 配额" : "按量付费"
        let tankCap = TokenTracker.formatTokens(AppSettings.oxygenTankCapacity)

        log("════════════════════════════════════════")
        log("Rockpile 启动 v\(version) (build \(build))")
        log("  macOS: \(osVersion)")
        log("  模式: \(role)")
        log("  O₂: \(o2Mode) / 容量 \(tankCap)")
        if !AppSettings.rockpileHost.isEmpty {
            log("  远程主机: \(AppSettings.rockpileHost)")
        }
        if let ip = SetupManager.getLocalIP() {
            log("  本机 IP: \(ip)")
        }
        log("  日志: \(logFile.path)")
        log("════════════════════════════════════════")
    }

    // MARK: - Heartbeat

    /// 定时记录运行状态，方便排查"某时段发生了什么"
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.logHeartbeat()
            }
        }
    }

    private func logHeartbeat() {
        let uptime = Int(Date().timeIntervalSince(launchTime))
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let uptimeStr = hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
        log("💓 心跳 | 运行 \(uptimeStr) | 累计事件 \(eventCount)")
    }

    // MARK: - Public API

    /// Log a general message
    func log(_ message: String) {
        let line = "[\(dateFormatter.string(from: Date()))] \(message)"
        appendLine(line)
    }

    /// Log an incoming socket event (raw data) with client info
    func logRawEvent(source: String, byteCount: Int, clientIP: String? = nil) {
        var msg = "📥 收到数据 [\(source)] \(byteCount) bytes"
        if let ip = clientIP {
            msg += " from \(ip)"
        }
        log(msg)
    }

    /// Log a parsed HookEvent
    func logEvent(_ event: HookEvent) {
        eventCount += 1
        var parts = ["📨 #\(eventCount) \(event.event)"]
        parts.append("会话=\(shortId(event.sessionId))")
        parts.append("状态=\(event.status)")
        if let tool = event.tool { parts.append("工具=\(tool)") }
        if let error = event.error { parts.append("❌ \(error)") }

        // Token 信息 — 对追踪 O₂ 问题关键
        var tokenParts: [String] = []
        if let daily = event.dailyTokensUsed { tokenParts.append("daily=\(TokenTracker.formatTokens(daily))") }
        if let input = event.inputTokens { tokenParts.append("in=\(input)") }
        if let output = event.outputTokens { tokenParts.append("out=\(output)") }
        if let cacheRead = event.cacheReadTokens { tokenParts.append("cache_r=\(cacheRead)") }
        if let cacheMake = event.cacheCreationTokens { tokenParts.append("cache_w=\(cacheMake)") }
        if !tokenParts.isEmpty {
            parts.append("tokens[\(tokenParts.joined(separator: ","))]")
        }

        if let rl = event.rateLimited, rl { parts.append("⚡RATE_LIMITED") }

        log(parts.joined(separator: " | "))
    }

    // MARK: - Session Lifecycle

    func logSessionCreated(id: String, total: Int) {
        log("🦞+ 新建会话: \(shortId(id)) (当前共 \(total) 个)")
    }

    func logSessionRemoved(id: String, reason: String, remaining: Int) {
        log("🦞- 移除会话: \(shortId(id)) [\(reason)] (剩余 \(remaining) 个)")
    }

    /// 会话结束摘要 — 持续时间、事件数、token 总量
    func logSessionSummary(id: String, duration: TimeInterval, activityCount: Int,
                           toolCalls: Int, totalTokens: Int) {
        let durationStr: String
        let minutes = Int(duration / 60)
        let seconds = Int(duration) % 60
        if minutes > 0 {
            durationStr = "\(minutes)m\(seconds)s"
        } else {
            durationStr = "\(seconds)s"
        }
        log("📊 会话摘要: \(shortId(id)) | 持续 \(durationStr) | \(activityCount) 事件 | \(toolCalls) 工具 | \(TokenTracker.formatTokens(totalTokens)) tokens")
    }

    func logSessionStateChange(id: String, from: String, to: String) {
        log("🔄 状态变化: \(shortId(id)) \(from) → \(to)")
    }

    // MARK: - O₂ Tracking

    /// O₂ 区间变化 — 帮助排查 token 追踪和 UI 显示问题
    func logOxygenZoneChange(sessionId: String, from: String, to: String, level: Double, used: Int, capacity: Int) {
        log("🫧 O₂ 区间: \(shortId(sessionId)) \(from) → \(to) (\(Int(level * 100))% | \(TokenTracker.formatTokens(used))/\(TokenTracker.formatTokens(capacity)))")
    }

    // MARK: - Network

    func logConnectionAccepted(source: String, clientIP: String? = nil) {
        var msg = "🔌 接受连接: \(source)"
        if let ip = clientIP {
            msg += " (\(ip))"
        }
        log(msg)
    }

    func logHTTPRequest(method: String, path: String, clientIP: String? = nil) {
        var msg = "🌐 HTTP \(method) \(path)"
        if let ip = clientIP {
            msg += " from \(ip)"
        }
        log(msg)
    }

    func logParseError(detail: String) {
        log("⚠️ 解析失败: \(detail)")
    }

    // MARK: - Configuration Changes

    func logConfigChange(key: String, oldValue: String, newValue: String) {
        log("⚙️ 配置变更: \(key) = \(oldValue) → \(newValue)")
    }

    // MARK: - Cleanup

    func logCleanup(removedCount: Int, ids: [String]) {
        if removedCount > 0 {
            log("🧹 清理 \(removedCount) 个过期会话: \(ids.map { shortId($0) }.joined(separator: ", "))")
        }
    }

    // MARK: - Plugin

    func logPluginInstall(success: Bool, path: String) {
        if success {
            log("🔧 插件安装成功: \(path)")
        } else {
            log("❌ 插件安装失败: \(path)")
        }
    }

    // MARK: - Command (反向通信)

    func logCommandSent(action: String, sessionId: String?, method: String) {
        let sid = sessionId.map { shortId($0) } ?? "default"
        log("📤 指令发送: \(action) | 会话=\(sid) | 方式=\(method)")
    }

    func logCommandResult(action: String, result: String) {
        log("📤 指令结果: \(action) | \(result)")
    }

    // MARK: - History

    func logHistoryRecord(sessionId: String, duration: String, toolCalls: Int, tokens: Int) {
        log("📋 足迹保存: \(shortId(sessionId)) | \(duration) | 工具×\(toolCalls) | \(TokenTracker.formatTokens(tokens))")
    }

    func logHistoryLoaded(count: Int) {
        log("📋 足迹加载: \(count) 条记录")
    }

    // MARK: - Export

    /// Returns the log file path
    var logFilePath: URL { logFile }

    /// Read all log content
    func readLogs() -> String {
        (try? String(contentsOf: logFile, encoding: .utf8)) ?? "(空日志)"
    }

    /// Export logs to a specified location (returns true on success)
    @discardableResult
    func exportLogs(to destination: URL) -> Bool {
        do {
            try FileManager.default.copyItem(at: logFile, to: destination)
            log("📤 日志已导出到: \(destination.path)")
            return true
        } catch {
            log("❌ 导出失败: \(error.localizedDescription)")
            return false
        }
    }

    /// Clear all logs
    func clearLogs() {
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
        log("🗑️ 日志已清空")
    }

    // MARK: - Private

    private func shortId(_ id: String) -> String {
        if id.count > 12 {
            return String(id.prefix(8)) + "…"
        }
        return id
    }

    private func appendLine(_ line: String) {
        // Also log to system console
        logger.info("\(line, privacy: .public)")

        // Buffer during rotation to prevent data loss
        if isRotating {
            rotationBuffer.append(line)
            return
        }

        // Rotate if needed (reopens handle after rotation)
        rotateIfNeeded()

        // Append via persistent handle
        writeLine(line)
    }

    private func writeLine(_ line: String) {
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = fileHandle {
            handle.write(data)
        } else {
            // Fallback: reopen handle
            openFileHandle()
            fileHandle?.write(data)
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? Int,
              size > maxLogSize else { return }

        isRotating = true

        // Close current handle before rotating
        fileHandle?.closeFile()
        fileHandle = nil

        let fm = FileManager.default
        // Rotate: .log.2 → delete, .log.1 → .log.2, .log → .log.1
        let log2 = logDir.appendingPathComponent("rockpile.log.2")
        let log1 = logDir.appendingPathComponent("rockpile.log.1")
        try? fm.removeItem(at: log2)
        if fm.fileExists(atPath: log1.path) {
            try? fm.moveItem(at: log1, to: log2)
        }
        try? fm.moveItem(at: logFile, to: log1)

        // Reopen handle for new log file
        openFileHandle()
        isRotating = false

        // Flush any lines buffered during rotation
        let buffered = rotationBuffer
        rotationBuffer.removeAll()
        for line in buffered {
            writeLine(line)
        }
    }
}
