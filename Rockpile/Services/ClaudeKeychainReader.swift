import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ClaudeKeychain")

/// Reads Claude Code OAuth token from macOS Keychain.
///
/// Claude Code stores credentials in Keychain under:
/// - service: "Claude Code-credentials"
/// - account: (varies)
///
/// The token can be used to query usage via Anthropic OAuth API.
@MainActor
enum ClaudeKeychainReader {

    /// Cached token to avoid repeated Keychain lookups
    private static var cachedToken: String?
    private static var lastReadTime: Date?
    private static var accessDenied = false
    private static let cacheTimeout: TimeInterval = 300 // 5 min

    /// Read the OAuth access_token from Claude Code's Keychain entry.
    /// Returns nil if not found or access is denied.
    static func readAccessToken() -> String? {
        // Don't re-prompt if user already denied Keychain access this session
        if accessDenied { return nil }

        // Check cache
        if let cached = cachedToken,
           let lastRead = lastReadTime,
           Date().timeIntervalSince(lastRead) < cacheTimeout {
            return cached
        }

        let token = readFromKeychain()
        cachedToken = token
        lastReadTime = Date()
        return token
    }

    /// Clear cached token (e.g. on auth failure)
    static func clearCache() {
        cachedToken = nil
        lastReadTime = nil
    }

    /// Check if a Claude OAuth token is available
    static var isAvailable: Bool {
        readAccessToken() != nil
    }

    // MARK: - Private

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [Data] else {
            if status == errSecItemNotFound {
                logger.info("No Claude Code credentials in Keychain")
            } else if status == errSecAuthFailed || status == -25293 {
                logger.warning("Keychain access denied — won't re-prompt this session")
                accessDenied = true
            } else {
                logger.info("Keychain query returned: \(status)")
            }
            return nil
        }

        // Try each item — look for one with access_token
        for data in items {
            guard let str = String(data: data, encoding: .utf8) else { continue }

            // Try parsing as JSON
            if let jsonData = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let accessToken = json["access_token"] as? String,
               !accessToken.isEmpty {
                logger.info("Found Claude OAuth token in Keychain")
                return accessToken
            }

            // Maybe the raw value IS the token
            if str.hasPrefix("sk-ant-") || str.count > 40 {
                logger.info("Found Claude token (raw) in Keychain")
                return str
            }
        }

        logger.info("No valid access_token found in Claude Keychain entries")
        return nil
    }
}
