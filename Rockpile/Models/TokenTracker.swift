import Foundation
import Observation

/// Token 用量追踪器 — 驱动 O₂ 氧气条显示
///
/// v2.0: 每个 tracker 绑定 `creatureType`，自动读取对应的 per-creature 设置：
/// - hermitCrab → `localOxygenMode` / `localOxygenTankCapacity`
/// - crawfish → `remoteOxygenMode` / `remoteOxygenTankCapacity`
/// - nil → 兼容旧全局设置
///
/// 支持两种 O₂ 模式：
/// - **Claude 限额模式**: 从 stats-cache.json 读取 dailyTokensUsed（每日配额追踪）
/// - **充值模式 (xAI/Google)**: 累加每次请求的 input/output/cache tokens（会话级追踪）
///
/// 氧气等级映射：
/// - ≥60% → 绿色（正常）
/// - 30%~60% → 黄色（警告）
/// - <30% → 红色（危险）
/// - 0% → K.O.（死亡动画）
@MainActor
@Observable
final class TokenTracker {
    /// Which creature this tracker belongs to (nil = legacy global tracker)
    var creatureType: CreatureType?

    /// Per-session cumulative token counts
    private(set) var sessionInputTokens: Int = 0
    private(set) var sessionOutputTokens: Int = 0
    private(set) var sessionCacheReadTokens: Int = 0
    private(set) var sessionCacheCreationTokens: Int = 0

    /// Daily aggregate from stats-cache.json (sent by plugin)
    private(set) var dailyTokensUsed: Int = 0

    /// Whether the API returned 429 (quota exhausted)
    private(set) var isRateLimited: Bool = false

    /// Last time usage data was updated
    private(set) var lastUpdateTime: Date = .distantPast

    /// xAI remaining balance in USD (from Usage API query)
    private(set) var remainingBalanceUSD: Double?

    // MARK: - Temporal Tracking (Deep Module — 吸收 burn rate/ETA/pace/velocity 复杂度)

    /// 时间戳 + 累计 token 快照（滑动窗口，用于计算 burn rate）
    private var tokenSnapshots: [(timestamp: Date, total: Int)] = []

    /// 会话开始时间（首次 recordUsage 时设置）
    private var sessionStartTime: Date?

    // MARK: - Feeding System

    /// Bonus tokens from feeding (offsets effectiveDailyUsed).
    /// Publicly settable for punishment system (triple-tap penalty).
    var feedBonusTokens: Int = 0

    /// Last time the crayfish was fed
    private var lastFeedTime: Date = .distantPast

    /// Cooldown between feedings (seconds)
    private static let feedCooldown: TimeInterval = RC.Feed.cooldown

    /// Feed timestamps within overfeed detection window
    private var recentFeedTimes: [Date] = []

    /// Whether currently in overfed state (stomach full, feeds rejected)
    private(set) var isOverfed: Bool = false

    /// When overfed state started (for recovery timer)
    private var overfedSince: Date = .distantPast

    /// Total tokens consumed in current session
    var sessionTotalTokens: Int {
        sessionInputTokens + sessionOutputTokens + sessionCacheReadTokens + sessionCacheCreationTokens
    }

    /// Per-creature O₂ mode: uses local/remote settings when creatureType is set.
    private var isClaudeQuotaMode: Bool {
        switch creatureType {
        case .hermitCrab: return AppSettings.localOxygenMode == "claude"
        case .crawfish:   return AppSettings.remoteOxygenMode == "claude"
        case nil:         return AppSettings.isClaudeQuotaMode
        }
    }

    /// Per-creature tank capacity.
    private var tankCapacity: Int {
        switch creatureType {
        case .hermitCrab: return AppSettings.localOxygenTankCapacity
        case .crawfish:   return AppSettings.remoteOxygenTankCapacity
        case nil:         return AppSettings.oxygenTankCapacity
        }
    }

    /// Effective usage based on O₂ mode setting.
    /// - Claude mode: prefers dailyTokensUsed from stats-cache.json (daily quota tracking),
    ///   falls back to session tokens if stats-cache data is unavailable (format changed, etc.)
    /// - Paid mode: uses accumulated per-request tokens (session-based tracking for xAI/Google etc.)
    var effectiveDailyUsed: Int {
        if isClaudeQuotaMode {
            // Prefer daily aggregate; fallback to session tokens if stats-cache returns 0
            if dailyTokensUsed > 0 { return dailyTokensUsed }
            return sessionTotalTokens
        }
        // Paid mode: accumulate from per-request data
        return sessionTotalTokens > 0 ? sessionTotalTokens : dailyTokensUsed
    }

    /// Whether we're in paid/accumulation mode
    var isPaidMode: Bool {
        !isClaudeQuotaMode
    }

    /// Oxygen level: 1.0 = full, 0.0 = depleted
    var oxygenLevel: Double {
        if isRateLimited { return 0.0 }

        let capacity = Double(max(tankCapacity, 1))
        let used = Double(max(0, effectiveDailyUsed - feedBonusTokens))
        return max(0.0, min(1.0, 1.0 - used / capacity))
    }

    /// Oxygen percentage (0-100)
    var oxygenPercent: Int {
        Int(oxygenLevel * 100)
    }

    /// Whether the crayfish should show distress
    var isLowOxygen: Bool {
        oxygenLevel < 0.3
    }

    /// Whether the crayfish should play death animation
    var isDead: Bool {
        oxygenLevel <= 0.0
    }

    /// Has received any usage data
    var hasUsageData: Bool {
        dailyTokensUsed > 0 || sessionTotalTokens > 0
    }

    /// Whether O₂ bar should be visible.
    /// 充值模式始终显示（方便观察预算），Claude 模式仅在有数据时显示。
    var shouldShowOxygen: Bool {
        isPaidMode || hasUsageData
    }

    // MARK: - Burn Rate & Predictions (Deep Module 公开面)

    /// Tank capacity exposed for UI display (日进度计算)
    var tankCapacityForDisplay: Int { tankCapacity }

    /// 会话持续时长（秒）
    var sessionDurationSeconds: TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// 格式化会话时长: "12m", "1h3m"
    var sessionDurationText: String {
        let total = Int(sessionDurationSeconds)
        if total >= 3600 {
            return "\(total / 3600)h\((total % 3600) / 60)m"
        } else if total >= 60 {
            return "\(total / 60)m"
        }
        return "\(max(total, 0))s"
    }

    /// 近 2 分钟 tokens/分钟（平滑值）。无数据时返回 0 — Define Errors Out。
    var burnRate: Double {
        let windowSize = RC.BurnRate.windowSize
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSize)
        let recent = tokenSnapshots.filter { $0.timestamp >= cutoff }
        guard recent.count >= RC.BurnRate.minDataPoints,
              let first = recent.first, let last = recent.last else { return 0 }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 10 else { return 0 }  // 至少 10 秒跨度
        let tokenDelta = Double(last.total - first.total)
        guard tokenDelta > 0 else { return 0 }
        return tokenDelta / (elapsed / 60.0)  // tokens per minute
    }

    /// 格式化消耗率: "2.1K/m", "0/m"
    var burnRateText: String {
        let rate = Int(burnRate)
        if rate == 0 { return "0/m" }
        return "\(Self.formatTokens(rate))/m"
    }

    /// 预计耗尽分钟数。burn rate 为 0 或无法计算时返回 nil。
    var etaMinutes: Double? {
        guard burnRate > 0 else { return nil }
        let remaining = Double(max(0, tankCapacity - effectiveDailyUsed + feedBonusTokens))
        guard remaining > 0 else { return 0 }
        return remaining / burnRate
    }

    /// 格式化 ETA: "~2.5h", "~18m", "<1m", nil
    var etaText: String? {
        guard let eta = etaMinutes else { return nil }
        if eta >= 60 {
            return String(format: "~%.1fh", eta / 60)
        } else if eta >= 1 {
            return "~\(Int(eta))m"
        }
        return "<1m"
    }

    /// 配速状态 — 对比 5 小时线性预算
    enum PaceStatus: String {
        case ahead    // 消耗速度超过可持续水平
        case onTrack  // ±20% 线性配速
        case behind   // 消耗低于预算
        case idle     // 无数据 / 零消耗
    }

    var paceStatus: PaceStatus {
        guard burnRate > 0 else { return .idle }
        let linearPace = Double(tankCapacity) / RC.BurnRate.dailyBudgetMinutes
        let ratio = burnRate / max(linearPace, 1)
        if ratio > 1.2 { return .ahead }
        if ratio < 0.8 { return .behind }
        return .onTrack
    }

    /// 速度趋势 — 近 1 分钟 vs 前 1 分钟
    enum VelocityTrend: String {
        case increasing  // >15% 加速
        case stable      // ±15% 内
        case decreasing  // >15% 减速
        case unknown     // 数据不足
    }

    var velocityTrend: VelocityTrend {
        let now = Date()
        let mid = now.addingTimeInterval(-60)
        let start = now.addingTimeInterval(-120)
        let recentHalf = tokenSnapshots.filter { $0.timestamp >= mid }
        let olderHalf = tokenSnapshots.filter { $0.timestamp >= start && $0.timestamp < mid }
        guard recentHalf.count >= 2, olderHalf.count >= 2 else { return .unknown }

        func rate(_ snapshots: [(timestamp: Date, total: Int)]) -> Double {
            guard let f = snapshots.first, let l = snapshots.last else { return 0 }
            let dt = l.timestamp.timeIntervalSince(f.timestamp)
            guard dt > 5 else { return 0 }
            return Double(l.total - f.total) / (dt / 60.0)
        }

        let recentRate = rate(recentHalf)
        let olderRate = rate(olderHalf)
        guard olderRate > 0 else {
            return recentRate > 0 ? .increasing : .unknown
        }
        let change = (recentRate - olderRate) / olderRate
        if change > RC.BurnRate.velocityThreshold { return .increasing }
        if change < -RC.BurnRate.velocityThreshold { return .decreasing }
        return .stable
    }

    /// 趋势箭头 UI
    var velocityArrow: String {
        switch velocityTrend {
        case .increasing: return "↑"
        case .stable:     return "→"
        case .decreasing: return "↓"
        case .unknown:    return ""
        }
    }

    /// O₂ 压力综合值 (0.0=平静, 1.0=极度紧张)
    /// 综合 oxygenLevel + burnRate pace + velocityTrend + ETA
    var oxygenStress: Double {
        if isDead { return 1.0 }
        if !hasUsageData { return 0.0 }

        // 基础压力: O₂ 越低压力越高
        var stress = 1.0 - oxygenLevel

        // 配速过快时增加压力
        if paceStatus == .ahead {
            stress = min(1.0, stress + 0.15)
        }

        // 加速中增加压力
        if velocityTrend == .increasing {
            stress = min(1.0, stress + 0.1)
        }

        // ETA 很短时额外增加压力
        if let eta = etaMinutes, eta < 30 {
            stress = min(1.0, stress + 0.2)
        }

        return stress
    }

    // MARK: - Temporal Snapshot Recording

    /// 记录时间快照（在各 record 方法中调用）
    private func recordSnapshot() {
        if sessionStartTime == nil {
            sessionStartTime = Date()
        }
        let now = Date()
        tokenSnapshots.append((timestamp: now, total: sessionTotalTokens))
        // 裁剪 5 分钟外的旧快照
        let cutoff = now.addingTimeInterval(-300)
        tokenSnapshots.removeAll { $0.timestamp < cutoff }
    }

    /// O₂ zone name for logging
    private var oxygenZoneName: String {
        if isDead { return "K.O." }
        switch oxygenLevel {
        case 0.6...:    return "正常"
        case 0.3..<0.6: return "警告"
        case 0.1..<0.3: return "危险"
        default:        return "临界"
        }
    }

    // MARK: - Update

    func recordUsage(from event: HookEvent, sessionId: String = "?") {
        let oldZone = oxygenZoneName

        // Per-request tokens
        if let input = event.inputTokens {
            sessionInputTokens += input
        }
        if let output = event.outputTokens {
            sessionOutputTokens += output
        }
        if let cacheRead = event.cacheReadTokens {
            sessionCacheReadTokens += cacheRead
        }
        if let cacheCreation = event.cacheCreationTokens {
            sessionCacheCreationTokens += cacheCreation
        }

        // Daily aggregate (replace, not accumulate — plugin sends current total)
        if let daily = event.dailyTokensUsed {
            dailyTokensUsed = daily
        }

        // Rate limit detection
        if let limited = event.rateLimited, limited {
            isRateLimited = true
        }

        lastUpdateTime = Date()
        recordSnapshot()

        // Log O₂ zone transitions
        let newZone = oxygenZoneName
        if newZone != oldZone {
            EventLogger.shared.logOxygenZoneChange(
                sessionId: sessionId,
                from: oldZone,
                to: newZone,
                level: oxygenLevel,
                used: effectiveDailyUsed,
                capacity: tankCapacity
            )
        }
    }

    /// Record remote usage from GatewayDashboard aggregate data (absolute values, not deltas).
    func recordRemoteUsage(inputTokens: Int, outputTokens: Int, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) {
        // Remote data is absolute — only update if it's greater (monotonically increasing)
        sessionInputTokens = max(sessionInputTokens, inputTokens)
        sessionOutputTokens = max(sessionOutputTokens, outputTokens)
        sessionCacheReadTokens = max(sessionCacheReadTokens, cacheReadTokens)
        sessionCacheCreationTokens = max(sessionCacheCreationTokens, cacheWriteTokens)
        lastUpdateTime = Date()
        recordSnapshot()
    }

    /// Record usage from provider Usage API query (absolute daily values).
    /// xAI 返回余额而非用量时，存储余额供 UI 显示。
    func recordAPIUsage(_ result: UsageQueryService.UsageResult) {
        let totalFromAPI = result.inputTokens + result.outputTokens + result.cachedInputTokens
        if totalFromAPI > 0 {
            // Anthropic / OpenAI: 返回今日累计 token
            dailyTokensUsed = max(dailyTokensUsed, totalFromAPI)
        }
        if let balance = result.remainingBalance {
            // xAI: 存储剩余余额供 UI 显示
            remainingBalanceUSD = balance
        }
        lastUpdateTime = result.queryTime
        recordSnapshot()
    }

    /// Set dailyTokensUsed from local stats-cache.json file read.
    /// Only updates if new value is larger (monotonically increasing within a day).
    func setDailyTokensFromFile(_ daily: Int) {
        if daily > dailyTokensUsed {
            dailyTokensUsed = daily
            lastUpdateTime = Date()
        }
    }

    /// Reset rate limit flag (e.g., when quota replenishes)
    func clearRateLimit() {
        isRateLimited = false
    }

    // MARK: - Feeding

    /// Whether feeding is currently available (not on cooldown, not dead, not overfed)
    var canFeed: Bool {
        !isDead && !isOverfed && Date().timeIntervalSince(lastFeedTime) >= Self.feedCooldown
    }

    /// Remaining cooldown seconds (0 if ready)
    var feedCooldownRemaining: TimeInterval {
        if isOverfed {
            return max(0, CreatureReactions.overfeedRecovery - Date().timeIntervalSince(overfedSince))
        }
        return max(0, Self.feedCooldown - Date().timeIntervalSince(lastFeedTime))
    }

    /// Feed the creature to restore 5% O2. Returns true if successful.
    @discardableResult
    func feed() -> Bool {
        // Check overfed recovery
        if isOverfed {
            if Date().timeIntervalSince(overfedSince) >= CreatureReactions.overfeedRecovery {
                isOverfed = false
                recentFeedTimes.removeAll()
            } else {
                return false
            }
        }
        guard canFeed else { return false }

        let now = Date()
        lastFeedTime = now

        // Track recent feeds for overfeed detection
        recentFeedTimes.append(now)
        recentFeedTimes.removeAll { now.timeIntervalSince($0) > CreatureReactions.overfeedWindow }

        // Trigger overfed state if threshold exceeded
        if recentFeedTimes.count >= CreatureReactions.overfeedThreshold {
            isOverfed = true
            overfedSince = now
        }

        // Add bonus fraction of tank capacity as bonus tokens
        let bonusAmount = Int(Double(tankCapacity) * RC.Feed.bonusFraction)
        feedBonusTokens = min(feedBonusTokens + bonusAmount, max(effectiveDailyUsed, 1))
        return true
    }

    /// Reset all counters (new session)
    func reset() {
        sessionInputTokens = 0
        sessionOutputTokens = 0
        sessionCacheReadTokens = 0
        sessionCacheCreationTokens = 0
        dailyTokensUsed = 0
        isRateLimited = false
        lastUpdateTime = .distantPast
        tokenSnapshots.removeAll()
        sessionStartTime = nil
    }

    // MARK: - Display Helpers

    /// Format USD balance: "$12.50", "$0.42"
    static func formatBalance(_ amount: Double) -> String {
        if amount >= 100 {
            return String(format: "$%.0f", amount)
        } else if amount >= 10 {
            return String(format: "$%.1f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    /// Format token count for display: "425K", "1.2M"
    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000
            return String(format: "%.1fM", m)
        } else if count >= 1_000 {
            let k = Double(count) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        }
        return "\(count)"
    }
}
