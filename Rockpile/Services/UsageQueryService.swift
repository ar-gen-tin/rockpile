import Foundation
import Observation

/// Token 用量 API 查询服务 — 定时轮询 AI 提供商的 Usage/Billing API
///
/// **支持的提供商**:
/// - Anthropic: Admin API Key → usage_report/messages (每日 token 用量)
/// - xAI: Management Key → prepaid/balance (剩余额度) + usage (token 用量)
/// - OpenAI: Admin Key → organization/usage/completions (预留接口)
///
/// **轮询策略**: 默认 5 分钟，错误时指数退避 (1→2→4→8→15 分钟)
/// **数据流**: API → UsageResult → TokenTracker.recordAPIUsage()
@MainActor
@Observable
final class UsageQueryService {
    static let shared = UsageQueryService()

    // MARK: - Types

    struct UsageResult: Sendable {
        let inputTokens: Int
        let outputTokens: Int
        let cachedInputTokens: Int
        let totalCost: Double?          // USD
        let remainingBalance: Double?   // USD, xAI only
        let queryTime: Date
    }

    enum QueryError: Error, CustomStringConvertible {
        case noAdminKey
        case invalidResponse(Int)
        case decodingFailed(String)
        case networkError(String)
        case notConfigured

        var description: String {
            switch self {
            case .noAdminKey:              return "需要 Management Key（非推理 Key）"
            case .invalidResponse(let c):  return "HTTP \(c)"
            case .decodingFailed(let m):   return "解析失败: \(m)"
            case .networkError(let m):     return "网络错误: \(m)"
            case .notConfigured:           return "未配置提供商"
            }
        }
    }

    // MARK: - Observable State

    private(set) var localResult: UsageResult?
    private(set) var remoteResult: UsageResult?
    private(set) var isQueryingLocal: Bool = false
    private(set) var isQueryingRemote: Bool = false
    var isQuerying: Bool { isQueryingLocal || isQueryingRemote }
    private(set) var localError: String?
    private(set) var remoteError: String?

    // MARK: - Private

    private var localTimer: Timer?
    private var remoteTimer: Timer?
    private var localBackoff: TimeInterval = 0
    private var remoteBackoff: TimeInterval = 0
    private static let maxBackoff: TimeInterval = 900  // 15 min

    private init() {}

    // MARK: - Polling Control

    func startPolling() {
        startPolling(for: .hermitCrab)
        startPolling(for: .crawfish)
    }

    func stopPolling() {
        localTimer?.invalidate()
        localTimer = nil
        remoteTimer?.invalidate()
        remoteTimer = nil
    }

    private func startPolling(for creature: CreatureType) {
        let provider = resolveProvider(for: creature)

        // Claude Subscription: 直接读取 stats-cache.json（无需 API Key）
        if provider == .claudeSubscription && creature == .hermitCrab {
            // 首次立即读取
            readStatsCache()
            // Try OAuth as well for richer data
            if ClaudeKeychainReader.isAvailable {
                Task { await queryClaudeOAuthUsage() }
            }
            // 每 30 秒刷新（本地文件，开销极小）
            let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.readStatsCache() }
            }
            localTimer?.invalidate()
            localTimer = timer
            return
        }

        // 其他提供商: 需要 Usage API 启用 + Admin Key
        let enabled = creature == .hermitCrab ? AppSettings.localUsageAPIEnabled : AppSettings.remoteUsageAPIEnabled
        guard enabled else { return }
        guard provider.supportsUsageAPI else { return }
        guard AdminKeyManager.hasKey(for: provider, creature: creature) else { return }

        // 首次立即查询
        Task { await queryNow(for: creature) }

        // 定时轮询
        let interval = creature == .hermitCrab ? AppSettings.localPollingInterval : AppSettings.remotePollingInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.queryNow(for: creature)
            }
        }
        if creature == .hermitCrab {
            localTimer?.invalidate()
            localTimer = timer
        } else {
            remoteTimer?.invalidate()
            remoteTimer = timer
        }
    }

    /// 立即查询指定生物的用量
    func queryNow(for creature: CreatureType) async {
        let provider = resolveProvider(for: creature)
        guard provider.supportsUsageAPI else {
            setError(creature, "Provider does not support Usage API")
            return
        }
        guard let adminKey = AdminKeyManager.readKey(for: provider, creature: creature) else {
            setError(creature, "No admin key configured")
            return
        }

        if creature == .hermitCrab { isQueryingLocal = true } else { isQueryingRemote = true }
        defer {
            if creature == .hermitCrab { isQueryingLocal = false } else { isQueryingRemote = false }
        }

        do {
            let result: UsageResult
            switch provider {
            case .claudeAPI:
                result = try await queryAnthropic(adminKey: adminKey)
            case .xAI:
                let teamId = AdminKeyManager.readTeamId(creature: creature) ?? ""
                result = try await queryXAI(managementKey: adminKey, teamId: teamId)
            case .openAI:
                result = try await queryOpenAI(adminKey: adminKey)
            default:
                throw QueryError.notConfigured
            }

            // 成功: 更新结果，重置退避
            if creature == .hermitCrab {
                localResult = result
                localError = nil
                localBackoff = 0
            } else {
                remoteResult = result
                remoteError = nil
                remoteBackoff = 0
            }

            // 注入 TokenTracker
            feedResultToTracker(result, creature: creature)

        } catch {
            let msg = (error as? QueryError)?.description ?? error.localizedDescription
            setError(creature, msg)

            // 指数退避
            if creature == .hermitCrab {
                localBackoff = min(localBackoff == 0 ? 60 : localBackoff * 2, Self.maxBackoff)
            } else {
                remoteBackoff = min(remoteBackoff == 0 ? 60 : remoteBackoff * 2, Self.maxBackoff)
            }
        }
    }

    // MARK: - Provider Implementations

    /// Anthropic: GET /v1/organizations/usage_report/messages
    private func queryAnthropic(adminKey: String) async throws -> UsageResult {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startStr = formatter.string(from: startOfDay)
        let endStr = formatter.string(from: now)

        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: startStr),
            URLQueryItem(name: "ending_at", value: endStr),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QueryError.networkError("非 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            throw QueryError.invalidResponse(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            throw QueryError.decodingFailed("无 data 数组")
        }

        // 累加今日所有 bucket
        var input = 0, output = 0, cached = 0
        for bucket in dataArr {
            if let results = bucket["results"] as? [[String: Any]] {
                for r in results {
                    input += r["input_tokens"] as? Int ?? 0
                    output += r["output_tokens"] as? Int ?? 0
                    cached += r["input_cached_tokens"] as? Int ?? 0
                }
            }
        }

        return UsageResult(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            totalCost: nil,
            remainingBalance: nil,
            queryTime: now
        )
    }

    /// xAI: GET /v1/billing/teams/{team_id}/prepaid/balance
    ///
    /// 需要 Management Key（非推理 Key）。推理 Key 会返回 401。
    /// 创建方式: console.x.ai → Settings → Management Keys
    private func queryXAI(managementKey: String, teamId: String) async throws -> UsageResult {
        guard !teamId.isEmpty else {
            throw QueryError.decodingFailed("未设置 Team ID")
        }

        // Query prepaid balance
        let url = URL(string: "https://management-api.x.ai/v1/billing/teams/\(teamId)/prepaid/balance")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QueryError.networkError("非 HTTP 响应")
        }

        if http.statusCode == 401 {
            throw QueryError.noAdminKey  // 推理 Key 无权访问 Management API
        }
        guard http.statusCode == 200 else {
            throw QueryError.invalidResponse(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QueryError.decodingFailed("JSON 解析失败")
        }

        // xAI balance response: look for remaining credits
        let balance = extractBalance(from: json)

        return UsageResult(
            inputTokens: 0,
            outputTokens: 0,
            cachedInputTokens: 0,
            totalCost: nil,
            remainingBalance: balance,
            queryTime: Date()
        )
    }

    /// OpenAI: GET /v1/organization/usage/completions (预留)
    private func queryOpenAI(adminKey: String) async throws -> UsageResult {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let startTime = Int(startOfDay.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startTime)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QueryError.networkError("非 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            throw QueryError.invalidResponse(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            throw QueryError.decodingFailed("无 data 数组")
        }

        var input = 0, output = 0, cached = 0
        for bucket in dataArr {
            if let results = bucket["results"] as? [[String: Any]] {
                for r in results {
                    input += r["input_tokens"] as? Int ?? 0
                    output += r["output_tokens"] as? Int ?? 0
                    cached += r["input_cached_tokens"] as? Int ?? 0
                }
            }
        }

        return UsageResult(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            totalCost: nil,
            remainingBalance: nil,
            queryTime: now
        )
    }

    // MARK: - Claude OAuth (Zero-Config)

    /// Query Claude usage via OAuth token from Keychain — zero API key needed.
    /// Uses Anthropic's OAuth usage endpoint.
    func queryClaudeOAuthUsage() async {
        guard let token = ClaudeKeychainReader.readAccessToken() else {
            return
        }

        isQueryingLocal = true
        defer { isQueryingLocal = false }

        do {
            let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw QueryError.networkError("非 HTTP 响应")
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                // Token expired or invalid — clear cache
                ClaudeKeychainReader.clearCache()
                throw QueryError.invalidResponse(http.statusCode)
            }
            guard http.statusCode == 200 else {
                throw QueryError.invalidResponse(http.statusCode)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw QueryError.decodingFailed("JSON 解析失败")
            }

            // Parse five_hour quota
            var utilization: Double = 0
            var resetsAt: Date?

            if let fiveHour = json["five_hour"] as? [String: Any] {
                utilization = fiveHour["utilization"] as? Double ?? 0
                if let resetStr = fiveHour["resets_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    resetsAt = formatter.date(from: resetStr)
                }
            }

            // Map utilization to O₂ system
            let tracker = StateMachine.shared.sessionStore.localTokenTracker
            let capacity = AppSettings.localOxygenTankCapacity
            let estimatedUsed = Int(utilization * Double(capacity))
            if estimatedUsed > tracker.dailyTokensUsed {
                tracker.setDailyTokensFromFile(estimatedUsed)
            }

            localError = nil
            localBackoff = 0

        } catch {
            let msg = (error as? QueryError)?.description ?? error.localizedDescription
            localError = msg
            localBackoff = min(localBackoff == 0 ? 60 : localBackoff * 2, Self.maxBackoff)
        }
    }

    // MARK: - Provider Resolution

    /// 解析提供商：优先 AppSettings 手动配置，否则使用自动检测
    private func resolveProvider(for creature: CreatureType) -> AIProvider {
        let rawValue = creature == .hermitCrab ? AppSettings.localProvider : AppSettings.remoteProvider
        if !rawValue.isEmpty, let provider = AIProvider(rawValue: rawValue) {
            return provider
        }
        // 自动检测
        return creature == .hermitCrab
            ? AIProviderDetector.detectLocalProvider()
            : AIProviderDetector.detectRemoteProvider()
    }

    // MARK: - Stats-Cache (Claude Subscription local file read)

    /// 直接读取 ~/.claude/stats-cache.json 获取当日用量
    /// Claude Subscription 不需要 Admin API Key，数据在本地
    ///
    /// stats-cache.json v2 格式:
    /// - dailyModelTokens: [{ date: "2026-03-10", tokensByModel: { "claude-opus-4-6": 14505 } }]
    /// - dailyActivity: [{ date: "2026-03-10", messageCount: 4129, toolCallCount: 840 }]
    /// - modelUsage: { "claude-opus-4-6": { inputTokens, outputTokens, cacheReadInputTokens, ... } }
    private func readStatsCache() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsPath = home.appendingPathComponent(".claude/stats-cache.json")

        guard let data = try? Data(contentsOf: statsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let tracker = StateMachine.shared.sessionStore.localTokenTracker

        // v1 格式兼容: { "dailyTokensUsed": 123456, ... }
        if let daily = json["dailyTokensUsed"] as? Int, daily > 0 {
            if daily > tracker.dailyTokensUsed {
                tracker.setDailyTokensFromFile(daily)
            }
            return
        }

        // v2 格式: 从 dailyModelTokens 提取 token 数
        // 优先级: 今日 > 昨日 > 最近一天（stats-cache 可能滞后 1-2 天）
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yesterdayStr = formatter.string(from: yesterday)

        if let dailyTokens = json["dailyModelTokens"] as? [[String: Any]] {
            let todayTokens = sumDayTokens(dailyTokens, date: todayStr)
            let yesterdayTokens = sumDayTokens(dailyTokens, date: yesterdayStr)
            let latestTokens = latestDayTokens(dailyTokens)

            let bestDaily = todayTokens > 0 ? todayTokens
                          : yesterdayTokens > 0 ? yesterdayTokens
                          : latestTokens

            if bestDaily > 0 && bestDaily > tracker.dailyTokensUsed {
                tracker.setDailyTokensFromFile(bestDaily)
            }
        }

        // 补充: 从 dailyActivity 提取消息数 × 估算倍数 (fallback)
        if tracker.dailyTokensUsed == 0, let dailyActivity = json["dailyActivity"] as? [[String: Any]] {
            let todayMessages = sumDayMessages(dailyActivity, date: todayStr)
            let yesterdayMessages = sumDayMessages(dailyActivity, date: yesterdayStr)
            let latestMessages = latestDayMessages(dailyActivity)
            let bestMessages = todayMessages > 0 ? todayMessages
                             : yesterdayMessages > 0 ? yesterdayMessages
                             : latestMessages

            // 估算: 平均每条消息 ~50 output tokens (基于历史数据推算)
            let estimatedTokens = bestMessages * 50
            if estimatedTokens > 0 && estimatedTokens > tracker.dailyTokensUsed {
                tracker.setDailyTokensFromFile(estimatedTokens)
            }
        }
    }

    /// 从 dailyModelTokens 数组中提取指定日期的 token 总和
    private func sumDayTokens(_ days: [[String: Any]], date: String) -> Int {
        for day in days {
            guard let d = day["date"] as? String, d == date,
                  let byModel = day["tokensByModel"] as? [String: Any] else { continue }
            var total = 0
            for (_, val) in byModel {
                if let n = val as? Int { total += n }
            }
            return total
        }
        return 0
    }

    /// 从 dailyActivity 数组中提取指定日期的消息数
    private func sumDayMessages(_ days: [[String: Any]], date: String) -> Int {
        for day in days {
            guard let d = day["date"] as? String, d == date,
                  let count = day["messageCount"] as? Int else { continue }
            return count
        }
        return 0
    }

    /// 从 dailyModelTokens 数组中取最后（最近）一天的 token 总和
    private func latestDayTokens(_ days: [[String: Any]]) -> Int {
        guard let last = days.last,
              let byModel = last["tokensByModel"] as? [String: Any] else { return 0 }
        var total = 0
        for (_, val) in byModel {
            if let n = val as? Int { total += n }
        }
        return total
    }

    /// 从 dailyActivity 数组中取最后（最近）一天的消息数
    private func latestDayMessages(_ days: [[String: Any]]) -> Int {
        guard let last = days.last,
              let count = last["messageCount"] as? Int else { return 0 }
        return count
    }

    // MARK: - Helpers

    private func extractBalance(from json: [String: Any]) -> Double? {
        // Try common patterns for balance response
        if let balance = json["remaining_credits"] as? Double { return balance }
        if let balance = json["balance"] as? Double { return balance }
        if let balanceObj = json["balance"] as? [String: Any],
           let amount = balanceObj["remaining_credits"] as? Double { return amount }
        if let balanceObj = json["balance"] as? [String: Any],
           let amount = balanceObj["amount"] as? Double { return amount }
        return nil
    }

    private func feedResultToTracker(_ result: UsageResult, creature: CreatureType) {
        let store = StateMachine.shared.sessionStore

        // 找到对应 creature 的 tracker
        let tracker: TokenTracker?
        if creature == .hermitCrab {
            tracker = store.localTokenTracker
        } else {
            tracker = store.remoteTokenTracker
        }

        tracker?.recordAPIUsage(result)
    }

    private func setError(_ creature: CreatureType, _ msg: String) {
        if creature == .hermitCrab {
            localError = msg
        } else {
            remoteError = msg
        }
    }
}
