import Foundation
import Security

/// Deployment role — replaces raw "local"/"monitor"/"host" strings
enum SetupRole: String, Sendable {
    case local
    case monitor
    case host
    case none = ""
}

enum AppSettings {
    private static let isMutedKey = "isMuted"
    private static let anthropicApiKeyKey = "anthropicApiKey"
    private static let setupCompletedKey = "setupCompleted"
    private static let setupCompletedVersionKey = "setupCompletedVersion"
    private static let setupRoleKey = "setupRole"
    private static let connectionModeKey = "connectionMode"
    private static let rockpileHostKey = "rockpileHost"
    private static let monitorHostKey = "monitorHost"
    private static let oxygenTankCapacityKey = "oxygenTankCapacity"
    private static let oxygenModeKey = "oxygenMode"
    private static let commandTokenKey = "commandToken"
    private static let commandPortKey = "commandPort"
    private static let gatewayPortKey = "gatewayPort"
    private static let gatewayTokenKey = "gatewayToken"
    private static let remoteEnabledKey = "remoteEnabled"
    private static let localOxygenModeKey = "localOxygenMode"
    private static let localOxygenTankCapacityKey = "localOxygenTankCapacity"
    private static let remoteOxygenModeKey = "remoteOxygenMode"
    private static let remoteOxygenTankCapacityKey = "remoteOxygenTankCapacity"
    private static let appLanguageKey = "appLanguage"

    // MARK: - Language

    /// App display language: "en" (default), "zh", "ja"
    static var appLanguage: String {
        get { UserDefaults.standard.string(forKey: appLanguageKey) ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: appLanguageKey) }
    }

    // MARK: - Audio

    static var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: isMutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: isMutedKey) }
    }

    static func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - API Keys

    /// Anthropic API key for emotion analysis via Claude Haiku.
    /// Stored in Keychain. Falls back to ANTHROPIC_API_KEY environment variable.
    static var anthropicApiKey: String? {
        get {
            // 1. Keychain (secure)
            if let saved = readKeychain(service: "com.rockpile.anthropic", account: "apiKey"), !saved.isEmpty {
                return saved
            }
            // 2. Legacy: migrate from UserDefaults to Keychain
            if let legacy = UserDefaults.standard.string(forKey: anthropicApiKeyKey), !legacy.isEmpty {
                writeKeychain(service: "com.rockpile.anthropic", account: "apiKey", value: legacy)
                UserDefaults.standard.removeObject(forKey: anthropicApiKeyKey)
                return legacy
            }
            // 3. Environment variable fallback
            return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        }
        set {
            if let value = newValue, !value.isEmpty {
                writeKeychain(service: "com.rockpile.anthropic", account: "apiKey", value: value)
            }
            // Clean up legacy UserDefaults entry
            UserDefaults.standard.removeObject(forKey: anthropicApiKeyKey)
        }
    }

    // MARK: - Setup & Onboarding

    /// Whether initial setup has been completed
    static var setupCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: setupCompletedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: setupCompletedKey)
            if newValue {
                // 记录完成设置时的版本号，下次更新时重新引导
                setupCompletedVersion = currentAppVersion
            }
        }
    }

    /// 上次完成引导时的 app 版本号
    static var setupCompletedVersion: String {
        get { UserDefaults.standard.string(forKey: setupCompletedVersionKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: setupCompletedVersionKey) }
    }

    /// 当前 app 版本号
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 是否需要显示引导（仅首次未完成时）
    /// 版本更新不再强制重新引导
    static var needsOnboarding: Bool {
        !setupCompleted
    }

    /// 是否属于版本更新（而非首次安装）
    static var isVersionUpdate: Bool {
        setupCompleted && setupCompletedVersion != currentAppVersion
    }

    /// 是否有新版本说明（非阻塞提示）
    static var hasNewVersionNotes: Bool {
        setupCompleted && !setupCompletedVersion.isEmpty && setupCompletedVersion != currentAppVersion
    }

    /// 当前版本的更新内容（每次发版手动维护）
    @MainActor
    static var versionNotes: [String] {
        (1...5).map { L10n.s("version.note\($0)") }
    }

    /// Setup role: .local | .monitor | .host | .none
    /// - local: Rockpile + Rockpile on same machine
    /// - monitor: This Mac monitors a remote Rockpile
    /// - host: This Mac runs Rockpile, sends events to remote monitor
    static var setupRole: SetupRole {
        get { SetupRole(rawValue: UserDefaults.standard.string(forKey: setupRoleKey) ?? "") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: setupRoleKey) }
    }

    /// Connection mode: "plugin" (Rockpile plugin with TCP/socket)
    static var connectionMode: String {
        get { UserDefaults.standard.string(forKey: connectionModeKey) ?? "plugin" }
        set { UserDefaults.standard.set(newValue, forKey: connectionModeKey) }
    }

    /// Rockpile host IP (when this Mac is the monitor)
    static var rockpileHost: String {
        get { UserDefaults.standard.string(forKey: rockpileHostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: rockpileHostKey) }
    }

    /// Monitor host IP (when this Mac is the Rockpile host)
    static var monitorHost: String {
        get { UserDefaults.standard.string(forKey: monitorHostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: monitorHostKey) }
    }

    // MARK: - O₂ Meter (Token Usage)

    /// O₂ mode: "claude" (daily quota warning) or "paid" (cumulative session usage)
    /// - claude: Uses daily_tokens_used from stats-cache.json (Claude Pro/Free daily limit)
    /// - paid: Uses accumulated per-request tokens (xAI, Google API, etc. pay-as-you-go)
    static var oxygenMode: String {
        get { UserDefaults.standard.string(forKey: oxygenModeKey) ?? "paid" }
        set { UserDefaults.standard.set(newValue, forKey: oxygenModeKey) }
    }

    /// Whether we're in Claude quota mode
    static var isClaudeQuotaMode: Bool { oxygenMode == "claude" }

    /// Whether we're in paid/cumulative mode
    static var isPaidMode: Bool { oxygenMode == "paid" }

    /// Oxygen tank capacity in tokens. Meaning depends on mode:
    /// - Claude mode: estimated daily token quota (e.g., 1M for Pro)
    /// - Paid mode: session budget you want to track against
    static var oxygenTankCapacity: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: oxygenTankCapacityKey)
            return value > 0 ? value : 1_000_000
        }
        set { UserDefaults.standard.set(newValue, forKey: oxygenTankCapacityKey) }
    }

    // MARK: - Dual O₂ (v2.0 — per-creature)

    /// Whether remote Openclaw connection is enabled
    static var remoteEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remoteEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: remoteEnabledKey) }
    }

    /// Local O₂ mode: "claude" (daily quota) or "paid" (cumulative)
    static var localOxygenMode: String {
        get { UserDefaults.standard.string(forKey: localOxygenModeKey) ?? oxygenMode }
        set { UserDefaults.standard.set(newValue, forKey: localOxygenModeKey) }
    }

    /// Local O₂ tank capacity (default 300K — Claude Code 典型重度日产出)
    static var localOxygenTankCapacity: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: localOxygenTankCapacityKey)
            return value > 0 ? value : 300_000
        }
        set { UserDefaults.standard.set(newValue, forKey: localOxygenTankCapacityKey) }
    }

    /// Remote O₂ mode: "claude" or "paid"
    static var remoteOxygenMode: String {
        get { UserDefaults.standard.string(forKey: remoteOxygenModeKey) ?? oxygenMode }
        set { UserDefaults.standard.set(newValue, forKey: remoteOxygenModeKey) }
    }

    /// Remote O₂ tank capacity (default 2M for paid API)
    static var remoteOxygenTankCapacity: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: remoteOxygenTankCapacityKey)
            return value > 0 ? value : 2_000_000
        }
        set { UserDefaults.standard.set(newValue, forKey: remoteOxygenTankCapacityKey) }
    }

    /// Convenience: is local in Claude quota mode?
    static var isLocalClaudeMode: Bool { localOxygenMode == "claude" }

    /// Convenience: is remote in paid mode?
    static var isRemotePaidMode: Bool { remoteOxygenMode == "paid" }

    // MARK: - Usage API Config (v2.1)

    /// 本地生物 AI 提供商 (AIProvider.rawValue)
    static var localProvider: String {
        get { UserDefaults.standard.string(forKey: "localProvider") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "localProvider") }
    }

    /// 远程生物 AI 提供商
    static var remoteProvider: String {
        get { UserDefaults.standard.string(forKey: "remoteProvider") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteProvider") }
    }

    /// 本地 Usage API 是否启用
    static var localUsageAPIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "localUsageAPIEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "localUsageAPIEnabled") }
    }

    /// 远程 Usage API 是否启用
    static var remoteUsageAPIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "remoteUsageAPIEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "remoteUsageAPIEnabled") }
    }

    /// 本地轮询间隔 (秒, 默认 300)
    static var localPollingInterval: TimeInterval {
        get {
            let v = UserDefaults.standard.double(forKey: "localPollingInterval")
            return v > 0 ? v : 300
        }
        set { UserDefaults.standard.set(newValue, forKey: "localPollingInterval") }
    }

    /// 远程轮询间隔 (秒, 默认 300)
    static var remotePollingInterval: TimeInterval {
        get {
            let v = UserDefaults.standard.double(forKey: "remotePollingInterval")
            return v > 0 ? v : 300
        }
        set { UserDefaults.standard.set(newValue, forKey: "remotePollingInterval") }
    }

    // MARK: - Notifications

    private static let notifyStateChangeKey = "notifyStateChange"
    private static let notifyO2LowKey = "notifyO2Low"
    private static let notifyO2CriticalKey = "notifyO2Critical"
    private static let notifyConnectionKey = "notifyConnection"
    private static let notifySessionCompleteKey = "notifySessionComplete"
    private static let notifyServiceStatusKey = "notifyServiceStatus"
    private static let notificationsEnabledKey = "notificationsEnabled"

    /// 通知总开关
    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil ? true : UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }

    /// 状态变化通知
    static var notifyStateChange: Bool {
        get { UserDefaults.standard.object(forKey: notifyStateChangeKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyStateChangeKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyStateChangeKey) }
    }

    /// O₂ 低阈值通知
    static var notifyO2Low: Bool {
        get { UserDefaults.standard.object(forKey: notifyO2LowKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyO2LowKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyO2LowKey) }
    }

    /// O₂ 临界阈值通知
    static var notifyO2Critical: Bool {
        get { UserDefaults.standard.object(forKey: notifyO2CriticalKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyO2CriticalKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyO2CriticalKey) }
    }

    /// 连接变化通知
    static var notifyConnection: Bool {
        get { UserDefaults.standard.object(forKey: notifyConnectionKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyConnectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyConnectionKey) }
    }

    /// 会话完成通知
    static var notifySessionComplete: Bool {
        get { UserDefaults.standard.object(forKey: notifySessionCompleteKey) == nil ? false : UserDefaults.standard.bool(forKey: notifySessionCompleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifySessionCompleteKey) }
    }

    /// 服务状态变化通知
    static var notifyServiceStatus: Bool {
        get { UserDefaults.standard.object(forKey: notifyServiceStatusKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyServiceStatusKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyServiceStatusKey) }
    }

    // MARK: - Custom Connections

    private static let customConnectionsKey = "customConnections"

    /// 自定义连接 JSON 存储
    static var customConnectionsData: Data? {
        get { UserDefaults.standard.data(forKey: customConnectionsKey) }
        set { UserDefaults.standard.set(newValue, forKey: customConnectionsKey) }
    }

    // MARK: - Command (反向通信)

    /// Bearer token for reverse command authentication
    /// Auto-generated on first access (32-char hex)
    static var commandToken: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: commandTokenKey), !existing.isEmpty {
                return existing
            }
            let token = generateCommandToken()
            UserDefaults.standard.set(token, forKey: commandTokenKey)
            return token
        }
        set { UserDefaults.standard.set(newValue, forKey: commandTokenKey) }
    }

    /// Reverse command port (plugin listens on this)
    static var commandPort: UInt16 {
        get {
            let value = UserDefaults.standard.integer(forKey: commandPortKey)
            return value > 0 ? UInt16(value) : 18793
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: commandPortKey) }
    }

    /// Generate a 32-character hex token
    static func generateCommandToken() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: - Gateway WebSocket

    /// Rockpile Gateway WebSocket port (default 18789)
    static var gatewayPort: UInt16 {
        get {
            let value = UserDefaults.standard.integer(forKey: gatewayPortKey)
            return value > 0 ? UInt16(value) : 18789
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: gatewayPortKey) }
    }

    /// Gateway auth token (for remote mode — stored in Keychain)
    static var gatewayToken: String {
        get { readKeychain(service: "com.rockpile.gateway", account: "token") ?? "" }
        set { writeKeychain(service: "com.rockpile.gateway", account: "token", value: newValue) }
    }

    // MARK: - Keychain Helpers

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private static func writeKeychain(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            // Add new item
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    /// Read gateway auth token from local ~/.rockpile/rockpile.json
    static func readLocalGatewayToken() -> String? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rockpile/rockpile.json")
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = json["gateway"] as? [String: Any],
              let auth = gateway["auth"] as? [String: Any],
              let token = auth["token"] as? String, !token.isEmpty else {
            return nil
        }
        return token
    }

    // MARK: - Display Helpers

    /// Localized role display name (shared across views)
    @MainActor
    static func roleName(_ role: SetupRole) -> String {
        switch role {
        case .local:   return L10n.s("role.local")
        case .monitor: return L10n.s("role.monitor")
        case .host:    return L10n.s("role.host")
        case .none:    return L10n.s("role.unknown")
        }
    }

    // MARK: - Reset

    /// Reset setup to trigger onboarding again
    static func resetSetup() {
        setupCompleted = false
        setupRole = .none
        rockpileHost = ""
        monitorHost = ""
    }
}
