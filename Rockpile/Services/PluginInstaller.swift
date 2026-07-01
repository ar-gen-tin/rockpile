import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "PluginInstaller")

/// Handles re-installation of the Rockpile plugin on subsequent launches.
/// First-time setup is handled by SetupManager during onboarding.
enum PluginInstaller {
    private static let rockpileDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".rockpile")
    private static let pluginDir = rockpileDir
        .appendingPathComponent("plugins")
        .appendingPathComponent("rockpile")
    /// Re-install plugin if Rockpile is present. Uses saved settings to determine mode.
    /// Note: Rockpile auto-discovers plugins in ~/.rockpile/plugins/ — no config registration needed.
    static func installIfNeeded() {
        guard FileManager.default.fileExists(atPath: rockpileDir.path) else {
            logger.info("Rockpile not installed (~/.rockpile not found)")
            return
        }

        switch AppSettings.setupRole {
        case .local:
            installLocalPlugin()
        case .host:
            let targetHost = AppSettings.monitorHost
            guard !targetHost.isEmpty else {
                logger.warning("Host role but no monitorHost configured")
                return
            }
            installTCPPlugin(targetHost: targetHost)
        case .monitor:
            // Monitor mode: nothing to install, this Mac only receives events
            break
        case .none:
            logger.info("No setup role configured, skipping plugin install")
        }
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: pluginDir)
        logger.info("Plugin uninstalled")
    }

    // MARK: - Shared Plugin JS

    /// Common plugin hook body JS shared between local and TCP modes.
    /// Includes reading ~/.claude/stats-cache.json for daily token usage (O₂ meter).
    /// Also used by SetupManager for first-time plugin generation.
    static let sharedPluginHookBody = """
          const fs = require("fs");
          const os = require("os");
          const statsPath = require("path").join(os.homedir(), ".claude", "stats-cache.json");

          // Read daily token usage from Claude Code stats cache
          function readDailyTokens() {
            try {
              const raw = fs.readFileSync(statsPath, "utf8");
              const stats = JSON.parse(raw);
              if (!stats.dailyModelTokens || !Array.isArray(stats.dailyModelTokens)) return 0;
              const today = new Date().toISOString().slice(0, 10);
              const entry = stats.dailyModelTokens.find(d => d.date === today);
              if (!entry || !entry.tokensByModel) return 0;
              return Object.values(entry.tokensByModel).reduce((a, b) => a + b, 0);
            } catch { return 0; }
          }

          const hooks = {
            before_agent_start: ["AgentStart", "working"],
            llm_input: ["LLMInput", "thinking"],
            llm_output: ["LLMOutput", "working"],
            before_tool_call: ["ToolCall", "working"],
            after_tool_call: ["ToolResult", "working"],
            agent_end: ["AgentEnd", "idle"],
            session_start: ["SessionStart", "idle"],
            session_end: ["SessionEnd", "ended"],
            subagent_spawned: ["SubagentSpawned", "working"],
            subagent_ended: ["SubagentEnded", "idle"],
            before_compaction: ["Compaction", "compacting"],
            message_received: ["MessageReceived", "working"],
          };

          // Hooks that carry token usage data
          const usageHooks = new Set(["llm_output", "after_tool_call"]);

          for (const [hook, [eventName, defaultStatus]] of Object.entries(hooks)) {
            api.registerHook(hook, async (ctx) => {
              const hasError = hook === "after_tool_call" && ctx.data?.error != null;
              const payload = {
                session_id: ctx.runId || ctx.sessionKey || "default",
                event: eventName,
                status: hasError ? "error" : defaultStatus,
                tool: ctx.data?.toolName,
                error: hasError ? String(ctx.data.error) : undefined,
                user_prompt: ctx.data?.prompt || ctx.data?.text,
                ts: Date.now(),
              };

              // Attach token usage for LLMOutput and ToolResult events
              if (usageHooks.has(hook)) {
                const usage = ctx.data?.usage;
                if (usage) {
                  payload.input_tokens = usage.input_tokens;
                  payload.output_tokens = usage.output_tokens;
                  payload.cache_read_tokens = usage.cache_read_input_tokens;
                  payload.cache_creation_tokens = usage.cache_creation_input_tokens;
                }
                payload.daily_tokens_used = readDailyTokens();
                // Detect rate limiting (429)
                if (ctx.data?.rateLimited || ctx.data?.status === 429) {
                  payload.rate_limited = true;
                }
              }

              sendEvent(payload);
            });
          }
        };
    """

    // MARK: - Local Plugin (Unix Socket)

    private static func installLocalPlugin() {
        let transportJS = """
        const { Socket } = require("net");
        const SOCKET_PATH = "/tmp/rockpile.sock";

        function sendEvent(payload) {
          const data = JSON.stringify(payload);
          function trySend(attempt) {
            const client = new Socket();
            client.connect(SOCKET_PATH, () => { client.write(data); client.end(); });
            client.on("error", (err) => {
              if (attempt < 3) setTimeout(() => trySend(attempt + 1), attempt * 1000);
            });
          }
          trySend(1);
        }

        module.exports = function rockpilePlugin(api) {
          console.log("[rockpile] Unix socket mode -> " + SOCKET_PATH);
        """

        writePlugin(transportJS: transportJS, logSuffix: "local")
    }

    // MARK: - TCP Plugin (Remote Monitoring)

    static func installTCPPlugin(targetHost: String, targetPort: UInt16 = 18790) {
        let safeHost = targetHost.replacingOccurrences(of: "\"", with: "")

        let transportJS = """
        const { Socket } = require("net");

        const ROCKPILE_HOST = process.env.ROCKPILE_HOST || "\(safeHost)";
        const ROCKPILE_PORT = parseInt(process.env.ROCKPILE_PORT || "\(targetPort)", 10);

        function sendEvent(payload) {
          const data = JSON.stringify(payload);
          function trySend(attempt) {
            const client = new Socket();
            client.connect(ROCKPILE_PORT, ROCKPILE_HOST, () => { client.write(data); client.end(); });
            client.on("error", (err) => {
              if (attempt < 3) setTimeout(() => trySend(attempt + 1), attempt * 1000);
            });
          }
          trySend(1);
        }

        module.exports = function rockpilePlugin(api) {
          console.log("[rockpile] TCP mode -> " + ROCKPILE_HOST + ":" + ROCKPILE_PORT);
        """

        writePlugin(transportJS: transportJS, logSuffix: "TCP -> \(safeHost):\(targetPort)")
    }

    // MARK: - Common Write Logic

    private static func writePlugin(transportJS: String, logSuffix: String) {
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create plugin dir: \(error.localizedDescription)")
            Task { @MainActor in EventLogger.shared.logPluginInstall(success: false, path: pluginDir.path) }
            return
        }

        let indexJS = transportJS + "\n" + sharedPluginHookBody

        let packageJSON = """
        {
          "name": "rockpile-plugin",
          "version": "1.0.0",
          "main": "index.js",
          "description": "Rockpile notch companion plugin for Rockpile"
        }
        """

        let indexPath = pluginDir.appendingPathComponent("index.js")
        let packagePath = pluginDir.appendingPathComponent("package.json")

        do {
            try indexJS.write(to: indexPath, atomically: true, encoding: .utf8)
            try packageJSON.write(to: packagePath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write plugin files: \(error.localizedDescription)")
            Task { @MainActor in EventLogger.shared.logPluginInstall(success: false, path: pluginDir.path) }
            return
        }

        guard fm.isReadableFile(atPath: indexPath.path),
              fm.isReadableFile(atPath: packagePath.path) else {
            logger.error("Plugin files not readable after install")
            Task { @MainActor in EventLogger.shared.logPluginInstall(success: false, path: pluginDir.path) }
            return
        }

        logger.info("Plugin installed (\(logSuffix, privacy: .public)) to \(pluginDir.path, privacy: .public)")
        Task { @MainActor in EventLogger.shared.logPluginInstall(success: true, path: pluginDir.path) }
    }

}
