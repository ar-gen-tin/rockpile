import Foundation

/// AI 服务商枚举 — 自动检测用户使用的 AI 平台
///
/// **产品逻辑**:
/// - 本地 (寄居蟹) 固定为 Claude Code，但计费模式不同:
///   - Claude Pro/Max/Team → 订阅配额模式 (claude mode)
///   - ANTHROPIC_API_KEY → API 按量模式 (paid mode)
/// - 远程 (小龙虾) 可能是任何 AI 平台
enum AIProvider: String, Sendable {
    case claudeSubscription  // Claude Pro/Max/Team — 日配额
    case claudeAPI           // Anthropic API Key — 按量
    case openAI              // OpenAI API — 按量
    case gemini              // Google Gemini API — 按量
    case xAI                 // Grok/xAI API — 按量
    case deepSeek            // DeepSeek API — 按量
    case unknown             // 未检测到

    /// L10n key for localized display name (use from @MainActor context)
    var displayNameKey: String {
        switch self {
        case .claudeSubscription: return "provider.claudeSub"
        case .claudeAPI:          return "provider.claudeAPI"
        case .openAI:             return "provider.openAI"
        case .gemini:             return "provider.gemini"
        case .xAI:               return "provider.xAI"
        case .deepSeek:          return "provider.deepSeek"
        case .unknown:           return "provider.unknown"
        }
    }

    /// Non-localized display name (safe from any isolation)
    var displayName: String {
        switch self {
        case .claudeSubscription: return "Claude Sub"
        case .claudeAPI:          return "Anthropic API"
        case .openAI:             return "OpenAI"
        case .gemini:             return "Gemini"
        case .xAI:               return "xAI"
        case .deepSeek:          return "DeepSeek"
        case .unknown:           return "AI"
        }
    }

    /// L10n key for localized billing label (use from @MainActor context)
    var billingLabelKey: String {
        switch self {
        case .claudeSubscription: return "provider.dailyQuota"
        case .unknown:            return ""
        default:                  return "provider.payAsYouGo"
        }
    }

    /// Non-localized billing label (safe from any isolation)
    var billingLabel: String {
        switch self {
        case .claudeSubscription: return "Quota"
        case .unknown:            return ""
        default:                  return "Pay"
        }
    }

    /// 推荐 O₂ 模式
    var recommendedOxygenMode: String {
        switch self {
        case .claudeSubscription: return "claude"
        default:                  return "paid"
        }
    }

    /// 推荐瓶容量 (tokens)
    var recommendedCapacity: Int {
        switch self {
        case .claudeSubscription: return 300_000   // Claude Code 典型重度日 ~300K output tokens
        case .claudeAPI:          return 2_000_000
        case .openAI:             return 2_000_000
        case .gemini:             return 2_000_000
        case .xAI:               return 2_000_000
        case .deepSeek:          return 5_000_000   // DeepSeek cheaper
        case .unknown:           return 1_000_000
        }
    }

    /// 是否为订阅模式
    var isSubscription: Bool { self == .claudeSubscription }

    /// 是否支持 Usage API 查询
    var supportsUsageAPI: Bool {
        switch self {
        case .claudeAPI, .openAI, .xAI: return true
        default: return false
        }
    }

    /// Admin Key 说明文本
    var adminKeyDescription: String {
        switch self {
        case .claudeAPI: return "Anthropic Admin Key (sk-ant-admin...)"
        case .openAI:    return "OpenAI Admin Key"
        case .xAI:       return "xAI Management Key"
        default:         return ""
        }
    }

    /// 是否需要额外的 Team ID (xAI)
    var needsTeamId: Bool { self == .xAI }
}

/// AI 服务商自动检测器
///
/// 检测顺序:
/// 1. `~/.claude/` 存在 → Claude Code 用户
/// 2. `~/.claude/stats-cache.json` 有每日数据 → 订阅模式
/// 3. 环境变量 `ANTHROPIC_API_KEY` → API 模式
/// 4. 其他环境变量 (`OPENAI_API_KEY`, `GEMINI_API_KEY` 等)
/// 5. `~/.config/` 下的配置文件
enum AIProviderDetector {

    /// 检测本地 AI 服务商 (寄居蟹)
    static func detectLocalProvider() -> AIProvider {
        // 0. 用户在设置/Onboarding 中手动选择的提供商
        let configured = AppSettings.localProvider
        if !configured.isEmpty, let provider = AIProvider(rawValue: configured) {
            return provider
        }

        let home = FileManager.default.homeDirectoryForCurrentUser

        // 1. Check for Claude Code installation
        let claudeDir = home.appendingPathComponent(".claude")
        let hasClaude = FileManager.default.fileExists(atPath: claudeDir.path)

        if hasClaude {
            // Check for stats-cache.json (indicates active Claude subscription)
            let statsCache = claudeDir.appendingPathComponent("stats-cache.json")
            if let data = try? Data(contentsOf: statsCache),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let _ = json["dailyTokensUsed"] as? Int {
                return .claudeSubscription
            }

            // Has Claude dir but no stats → might be API key mode
            if hasEnvKey("ANTHROPIC_API_KEY") {
                return .claudeAPI
            }

            // Claude dir exists → assume subscription (most common)
            return .claudeSubscription
        }

        // 2. Check API keys in environment
        if hasEnvKey("ANTHROPIC_API_KEY") { return .claudeAPI }
        if hasEnvKey("OPENAI_API_KEY")    { return .openAI }
        if hasEnvKey("GEMINI_API_KEY") || hasEnvKey("GOOGLE_API_KEY") { return .gemini }
        if hasEnvKey("XAI_API_KEY")       { return .xAI }
        if hasEnvKey("DEEPSEEK_API_KEY")  { return .deepSeek }

        return .unknown
    }

    /// 检测远程 AI 服务商 (小龙虾)
    /// 优先读取用户配置 (AppSettings)，否则尝试环境变量
    static func detectRemoteProvider() -> AIProvider {
        // 1. 用户在设置/Onboarding 中手动选择的提供商
        let configured = AppSettings.remoteProvider
        if !configured.isEmpty, let provider = AIProvider(rawValue: configured) {
            return provider
        }
        // 2. Fallback: 环境变量
        if hasEnvKey("OPENAI_API_KEY")    { return .openAI }
        if hasEnvKey("XAI_API_KEY")       { return .xAI }
        if hasEnvKey("GEMINI_API_KEY") || hasEnvKey("GOOGLE_API_KEY") { return .gemini }
        if hasEnvKey("DEEPSEEK_API_KEY")  { return .deepSeek }
        if hasEnvKey("ANTHROPIC_API_KEY") { return .claudeAPI }
        return .unknown
    }

    /// 首次启动时自动配置 O₂ 参数
    static func autoConfigureIfNeeded() {
        let key = "aiProviderAutoConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let local = detectLocalProvider()
        AppSettings.localOxygenMode = local.recommendedOxygenMode
        AppSettings.localOxygenTankCapacity = local.recommendedCapacity

        let remote = detectRemoteProvider()
        AppSettings.remoteOxygenMode = remote.recommendedOxygenMode
        AppSettings.remoteOxygenTankCapacity = remote.recommendedCapacity

        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Helpers

    private static func hasEnvKey(_ name: String) -> Bool {
        if let val = ProcessInfo.processInfo.environment[name], !val.isEmpty {
            return true
        }
        return false
    }
}
