import Foundation
import Security

/// Admin/Management API Key 安全存储 — 基于 macOS Keychain
///
/// 三家 AI 提供商都需要**管理员级别 API Key**（与推理 Key 不同）:
/// - Anthropic: Admin API Key (sk-ant-admin...)
/// - OpenAI: Admin API Key
/// - xAI: Management API Key
///
/// 每个生物 + 提供商组合独立存储
enum AdminKeyManager {

    // MARK: - Public API

    /// 存储 admin key 到 Keychain
    static func storeKey(for provider: AIProvider, creature: CreatureType, key: String) {
        writeKeychain(service: service(provider, creature), account: "adminKey", value: key)
    }

    /// 从 Keychain 读取 admin key
    static func readKey(for provider: AIProvider, creature: CreatureType) -> String? {
        readKeychain(service: service(provider, creature), account: "adminKey")
    }

    /// 检查是否已存储 key
    static func hasKey(for provider: AIProvider, creature: CreatureType) -> Bool {
        readKey(for: provider, creature: creature) != nil
    }

    /// 删除已存储的 key
    static func deleteKey(for provider: AIProvider, creature: CreatureType) {
        deleteKeychain(service: service(provider, creature), account: "adminKey")
    }

    /// 存储 xAI Team ID (非敏感，用 UserDefaults)
    static func storeTeamId(_ teamId: String, creature: CreatureType) {
        let key = creature == .hermitCrab ? "localXAITeamId" : "remoteXAITeamId"
        UserDefaults.standard.set(teamId, forKey: key)
    }

    /// 读取 xAI Team ID
    static func readTeamId(creature: CreatureType) -> String? {
        let key = creature == .hermitCrab ? "localXAITeamId" : "remoteXAITeamId"
        return UserDefaults.standard.string(forKey: key)
    }

    // MARK: - Private

    private static func service(_ provider: AIProvider, _ creature: CreatureType) -> String {
        "com.rockpile.admin.\(provider.rawValue).\(creature.rawValue)"
    }

    /// File-based fallback path: ~/.rockpile/keys/<service>.key
    /// Use when Keychain isn't available (e.g. headless SSH deploy)
    private static let keysDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rockpile/keys")
    }()

    private static func readKeychain(service: String, account: String) -> String? {
        // 1. Try Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8) {
            return str
        }

        // 2. File-based fallback: ~/.rockpile/keys/<service>.key
        let filePath = keysDir.appendingPathComponent("\(service).key")
        if let str = try? String(contentsOf: filePath, encoding: .utf8) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func writeKeychain(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private static func deleteKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
