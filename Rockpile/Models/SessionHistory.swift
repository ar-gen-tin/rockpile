import Foundation
import Observation

/// A persistent record of a completed session (conversation).
/// Stores metadata (not content) for the history list.
struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let sessionId: String
    let startTime: Date
    let endTime: Date
    let toolCallCount: Int
    let activityCount: Int
    let totalTokens: Int
    /// Unique tool names used in this session (e.g. ["bash", "edit", "grep"])
    let toolNames: [String]

    // v1.3: Token 明细（Optional — 旧记录兼容为 nil）
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?
    let modelName: String?

    // v2.0: 生物类型（Optional — 旧记录兼容为 nil → 默认 crawfish）
    let creatureType: CreatureType?

    /// Resolved creature type (defaults to crawfish for legacy records)
    var resolvedCreatureType: CreatureType {
        creatureType ?? .crawfish
    }

    /// Whether this record has per-category token breakdown
    var hasTokenBreakdown: Bool {
        inputTokens != nil || outputTokens != nil
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Compact duration: "2m15s" / "45s" / "<1s"
    var durationText: String {
        let total = Int(duration)
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            return "\(h)h\(m)m"
        } else if total >= 60 {
            let m = total / 60
            let s = total % 60
            return s > 0 ? "\(m)m\(s)s" : "\(m)m"
        } else if total > 0 {
            return "\(total)s"
        }
        return "<1s"
    }

    /// Tools summary: "bash·edit·grep" or "无工具"
    var toolSummary: String {
        if toolNames.isEmpty { return "" }
        return toolNames.prefix(3).joined(separator: "·") +
               (toolNames.count > 3 ? " +\(toolNames.count - 3)" : "")
    }

    /// Smart time display: today → "14:32", yesterday → "Yesterday 14:32", older → "3/8 14:32"
    /// Note: Uses short English format (concurrency-safe). Localized display
    /// is available via `localizedSmartTimeText` from @MainActor context.
    var smartTimeText: String {
        let cal = Calendar.current
        let time = Self.shortTimeFormatter.string(from: endTime)
        if cal.isDateInToday(endTime) {
            return time
        } else if cal.isDateInYesterday(endTime) {
            return "Yest \(time)"
        } else {
            let date = Self.shortDateFormatter.string(from: endTime)
            return "\(date) \(time)"
        }
    }

    /// Whether this record is worth showing (has meaningful activity)
    var isMeaningful: Bool {
        totalTokens > 0 || toolCallCount > 0 || activityCount >= 3
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
}

// MARK: - Localized Display (View-layer)

extension SessionRecord {
    /// Localized duration text for Views (@MainActor context).
    @MainActor
    var localizedDurationText: String {
        let total = Int(duration)
        let sec = L10n.s("time.second")
        let min = L10n.s("time.minute")
        let hr = L10n.s("time.hour")
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            return "\(h)\(hr)\(m)\(min)"
        } else if total >= 60 {
            let m = total / 60
            let s = total % 60
            return s > 0 ? "\(m)\(min)\(s)\(sec)" : "\(m)\(min)"
        } else if total > 0 {
            return "\(total)\(sec)"
        }
        return L10n.s("time.lessThan1s")
    }

    /// Localized smart time text for Views (@MainActor context).
    @MainActor
    var localizedSmartTimeText: String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: endTime)
        if cal.isDateInToday(endTime) {
            return time
        } else if cal.isDateInYesterday(endTime) {
            return "\(L10n.s("time.yesterday")) \(time)"
        } else {
            formatter.dateFormat = "M/d"
            let date = formatter.string(from: endTime)
            return "\(date) \(time)"
        }
    }
}

/// Manages persistent session history on disk.
/// Records are saved to ~/Library/Application Support/Rockpile/session-history.json
@MainActor
@Observable
final class SessionHistory {
    static let shared = SessionHistory()

    private(set) var records: [SessionRecord] = []
    private let fileURL: URL
    private static let maxRecords = 100

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Application Support/Rockpile")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session-history.json")
        load()
    }

    func addRecord(from session: SessionData) {
        let toolCallActivities = session.activities.filter { $0.type == .toolCall }
        let toolCalls = toolCallActivities.count
        let startTime = session.activities.first?.timestamp ?? session.lastEventTime

        // Extract unique tool names in order of first use
        var seenTools = Set<String>()
        var toolNames: [String] = []
        for activity in toolCallActivities {
            let name = activity.detail
            if !seenTools.contains(name) {
                seenTools.insert(name)
                toolNames.append(name)
            }
        }

        let tracker = session.tokenTracker
        let record = SessionRecord(
            id: UUID(),
            sessionId: session.id,
            startTime: startTime,
            endTime: Date(),
            toolCallCount: toolCalls,
            activityCount: session.activities.count,
            totalTokens: tracker.sessionTotalTokens,
            toolNames: toolNames,
            inputTokens: tracker.sessionInputTokens > 0 ? tracker.sessionInputTokens : nil,
            outputTokens: tracker.sessionOutputTokens > 0 ? tracker.sessionOutputTokens : nil,
            cacheReadTokens: tracker.sessionCacheReadTokens > 0 ? tracker.sessionCacheReadTokens : nil,
            cacheCreationTokens: tracker.sessionCacheCreationTokens > 0 ? tracker.sessionCacheCreationTokens : nil,
            modelName: nil,
            creatureType: session.creatureType
        )

        // Skip trivial sessions: no tokens, no tools, very few activities
        guard record.isMeaningful else {
            EventLogger.shared.log("📋 足迹跳过: \(session.id.prefix(8))… (无有效数据)")
            return
        }

        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        save()

        EventLogger.shared.logHistoryRecord(
            sessionId: record.sessionId,
            duration: record.durationText,
            toolCalls: toolCalls,
            tokens: record.totalTokens
        )
    }

    func clearHistory() {
        records.removeAll()
        save()
    }

    // MARK: - Aggregates (日汇总 & 趋势)

    /// 今日累计 tokens
    var todayTotalTokens: Int {
        let cal = Calendar.current
        return records
            .filter { cal.isDateInToday($0.endTime) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// 昨日累计 tokens
    var yesterdayTotalTokens: Int {
        let cal = Calendar.current
        return records
            .filter { cal.isDateInYesterday($0.endTime) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// 日环比趋势: >0.1 增长, <-0.1 减少, nil 无数据
    var dayOverDayTrend: Double? {
        let yesterday = yesterdayTotalTokens
        guard yesterday > 0 else { return todayTotalTokens > 0 ? 1.0 : nil }
        return Double(todayTotalTokens - yesterday) / Double(yesterday)
    }

    private func load() {
        // Try main file first
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            records = decoded
            EventLogger.shared.logHistoryLoaded(count: records.count)
            return
        }
        // Main file corrupted or missing — try backup
        let backupURL = fileURL.appendingPathExtension("bak")
        if let data = try? Data(contentsOf: backupURL),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            records = decoded
            EventLogger.shared.log("📋 足迹从备份恢复: \(records.count) 条记录")
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(records) else { return }

        // Atomic write: temp file → backup existing → rename
        let tempURL = fileURL.appendingPathExtension("tmp")
        let backupURL = fileURL.appendingPathExtension("bak")
        let fm = FileManager.default

        do {
            try data.write(to: tempURL)
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: backupURL)
                try? fm.moveItem(at: fileURL, to: backupURL)
            }
            try fm.moveItem(at: tempURL, to: fileURL)
        } catch {
            EventLogger.shared.log("❌ 足迹保存失败: \(error.localizedDescription)")
            // Clean up temp file
            try? fm.removeItem(at: tempURL)
        }
    }
}
