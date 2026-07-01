import Foundation

struct HookEvent: Decodable, Sendable {
    let sessionId: String
    let event: String
    let status: String
    let ts: Int?
    let tool: String?
    let error: String?
    let userPrompt: String?
    let cwd: String?

    // Token usage (per-request, from plugin)
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?

    // Daily aggregate — only populated by legacy JS plugin (PluginInstaller),
    // NOT by bash hook (HookInstaller). UsageQueryService reads stats-cache directly.
    let dailyTokensUsed: Int?

    // Rate limit flag (429 detected)
    let rateLimited: Bool?

    // Permission handling (P5)
    let toolUseId: String?
    let toolInput: [String: String]?

    /// Direct initializer — avoids JSON round-trip when synthesizing events (e.g. GatewaySessionRouter).
    init(sessionId: String, event: String, status: String, tool: String? = nil) {
        self.sessionId = sessionId
        self.event = event
        self.status = status
        self.ts = nil
        self.tool = tool
        self.error = nil
        self.userPrompt = nil
        self.cwd = nil
        self.inputTokens = nil
        self.outputTokens = nil
        self.cacheReadTokens = nil
        self.cacheCreationTokens = nil
        self.dailyTokensUsed = nil
        self.rateLimited = nil
        self.toolUseId = nil
        self.toolInput = nil
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case event, status, ts, tool, error, cwd
        case userPrompt = "user_prompt"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case dailyTokensUsed = "daily_tokens_used"
        case rateLimited = "rate_limited"
        case toolUseId = "tool_use_id"
        case toolInput = "tool_input"
    }
}
