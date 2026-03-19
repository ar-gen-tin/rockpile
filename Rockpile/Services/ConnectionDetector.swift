import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ConnectionDetector")

/// 连接类型自动检测 — 基于 URL 前缀和端口特征
///
/// 检测逻辑：
/// 1. URL scheme 前缀 (ws://, wss://, http://, https://)
/// 2. 端口特征 (:80, :443, :8080 → HTTP; 其他 → TCP)
/// 3. 尝试连接判断 (fallback)
enum ConnectionDetector {

    /// 检测连接类型 — async 允许网络探测
    static func detect(url: String) async -> ConnectionType {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Scheme-based detection
        if trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://") {
            return .webSocket
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .http
        }

        // 2. Port-based heuristic
        if let portRange = trimmed.range(of: #":(\d+)"#, options: .regularExpression) {
            let portStr = trimmed[portRange].dropFirst() // drop ":"
            if let port = UInt16(portStr) {
                switch port {
                case 80, 443, 8080, 8443, 3000, 5000:
                    return .http
                default:
                    return .tcp
                }
            }
        }

        // 3. Try HTTP HEAD request as fallback
        if let testURL = URL(string: "http://\(trimmed)") {
            var request = URLRequest(url: testURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...599).contains(httpResponse.statusCode) {
                    return .http
                }
            } catch {
                logger.info("HTTP probe failed for \(trimmed): \(error.localizedDescription)")
            }
        }

        return .unknown
    }

    /// 验证 URL 是否格式有效
    static func isValidURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Accept bare host:port
        if trimmed.range(of: #"^[\w\.\-]+:\d+$"#, options: .regularExpression) != nil {
            return true
        }

        // Accept full URLs
        return URL(string: trimmed) != nil
    }
}
