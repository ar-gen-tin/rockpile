import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "EmotionAnalyzer")

// MARK: - API Response Types

private struct HaikuResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let text: String?
    }
}

private struct EmotionResponse: Decodable {
    let emotion: String
    let intensity: Double
}

// MARK: - EmotionAnalyzer

@MainActor
final class EmotionAnalyzer {
    static let shared = EmotionAnalyzer()

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    private static let systemPrompt = """
        Classify the emotional tone of the user's message into exactly one emotion and an intensity score.
        Emotions: happy, sad, neutral.
        Happy: explicit praise ("great job", "thank you!"), gratitude, celebration, positive profanity ("LETS FUCKING GO").
        Sad: frustration, anger, insults, complaints, feeling stuck, disappointment, negative profanity.
        Neutral: instructions, requests, task descriptions, questions, enthusiasm about work, factual statements. \
        Exclamation marks or urgency about a task do NOT make it happy — only genuine positive sentiment toward the AI or outcome does.
        Default to neutral when unsure. Most coding instructions are neutral regardless of tone.
        Intensity: 0.0 (barely noticeable) to 1.0 (very strong). \
        ALL CAPS text indicates stronger emotion — increase intensity by 0.2-0.3 compared to the same message in lowercase.
        Reply with ONLY valid JSON: {"emotion": "...", "intensity": ...}
        """

    // MARK: - Response Cache (v2.1: 避免对相似 prompt 重复调 API)

    /// LRU 缓存 — key 为 prompt 前 200 字符的归一化形式，避免 API 重复调用
    private var responseCache: [(key: String, result: (ClawEmotion, Double), time: Date)] = []
    private static let maxCacheSize = 20
    private static let cacheTTL: TimeInterval = 300  // 5 分钟过期

    private init() {}

    // MARK: - Public

    /// Task-level timeout (seconds) — guards against DNS/TLS hangs beyond URLRequest.timeoutInterval
    private static let taskTimeout: TimeInterval = 12.0

    func analyze(_ prompt: String) async -> (emotion: ClawEmotion, intensity: Double) {
        let start = ContinuousClock.now

        guard let apiKey = AppSettings.anthropicApiKey, !apiKey.isEmpty else {
            logger.info("No Anthropic API key configured, skipping emotion analysis")
            return (.neutral, 0.0)
        }

        // v2.1: 检查缓存 — 相同/相似 prompt 直接返回
        let cacheKey = Self.normalizeCacheKey(prompt)
        if let cached = lookupCache(key: cacheKey) {
            logger.info("Emotion cache hit: \(cached.0.rawValue, privacy: .public) @ \(cached.1)")
            return cached
        }

        do {
            let result = try await withThrowingTaskGroup(
                of: (emotion: ClawEmotion, intensity: Double).self
            ) { group in
                group.addTask {
                    try await self.callHaiku(prompt: prompt, apiKey: apiKey)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(Self.taskTimeout))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let elapsed = ContinuousClock.now - start
            logger.info("Emotion analysis took \(elapsed, privacy: .public): \(result.emotion.rawValue) @ \(result.intensity)")

            // 缓存结果
            insertCache(key: cacheKey, result: result)

            return result
        } catch {
            let elapsed = ContinuousClock.now - start
            logger.error("Haiku API failed (\(elapsed, privacy: .public)): \(error.localizedDescription)")
            return (.neutral, 0.0)
        }
    }

    // MARK: - Cache Helpers

    private static func normalizeCacheKey(_ prompt: String) -> String {
        // 取前 200 字符，统一小写，去除多余空白
        let trimmed = String(prompt.prefix(200))
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return trimmed
    }

    private func lookupCache(key: String) -> (ClawEmotion, Double)? {
        let now = Date()
        // 清除过期条目
        responseCache.removeAll { now.timeIntervalSince($0.time) > Self.cacheTTL }
        return responseCache.first { $0.key == key }?.result
    }

    private func insertCache(key: String, result: (ClawEmotion, Double)) {
        // 移除重复 key
        responseCache.removeAll { $0.key == key }
        responseCache.append((key: key, result: result, time: Date()))
        // LRU 淘汰
        if responseCache.count > Self.maxCacheSize {
            responseCache.removeFirst()
        }
    }

    // MARK: - Private

    private func callHaiku(prompt: String, apiKey: String) async throws -> (emotion: ClawEmotion, intensity: Double) {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 50,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmotionAnalyzerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            logger.error("Haiku API returned \(httpResponse.statusCode): \(body, privacy: .public)")
            throw EmotionAnalyzerError.httpError(httpResponse.statusCode)
        }

        let haikuResponse = try JSONDecoder().decode(HaikuResponse.self, from: data)

        guard let text = haikuResponse.content.first?.text else {
            throw EmotionAnalyzerError.noContent
        }

        let jsonString = Self.extractJSON(from: text)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw EmotionAnalyzerError.invalidJSON(text)
        }

        let emotionResponse = try JSONDecoder().decode(EmotionResponse.self, from: jsonData)

        let emotion = Self.mapEmotion(emotionResponse.emotion)
        let intensity = min(1.0, max(0.0, emotionResponse.intensity))

        return (emotion, intensity)
    }

    private static func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code blocks
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract { ... }
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        return cleaned
    }

    private static func mapEmotion(_ raw: String) -> ClawEmotion {
        switch raw.lowercased() {
        case "happy":  return .happy
        case "sad":    return .sad
        case "angry":  return .angry
        default:       return .neutral
        }
    }
}

// MARK: - Errors

private enum EmotionAnalyzerError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case noContent
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid HTTP response"
        case .httpError(let code): return "HTTP \(code)"
        case .noContent: return "No content in Haiku response"
        case .invalidJSON(let raw): return "Invalid JSON: \(raw)"
        }
    }
}
