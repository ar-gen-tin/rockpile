import { Socket } from "net";

// ── Connection config ─────────────────────────────────────────────
// Set ROCKPILE_HOST to your Mac's IP to use TCP (remote mode).
// Leave unset to use Unix socket (local mode, same machine).
//
// Examples:
//   export ROCKPILE_HOST=192.168.1.100   → TCP to that IP:18790
//   export ROCKPILE_HOST=                 → Unix socket /tmp/rockpile.sock
//
const ROCKPILE_HOST = process.env.ROCKPILE_HOST || "";
const ROCKPILE_PORT = parseInt(process.env.ROCKPILE_PORT || "18790", 10);
const SOCKET_PATH = "/tmp/rockpile.sock";

interface PluginContext {
  runId?: string;
  sessionKey?: string;
  data?: Record<string, any>;
}

interface PluginApi {
  registerHook(event: string, handler: (ctx: PluginContext) => Promise<void>): void;
}

function sendEvent(payload: Record<string, unknown>): void {
  const client = new Socket();
  const data = JSON.stringify(payload);

  const onConnect = () => {
    client.write(data);
    client.end();
  };

  client.on("error", () => {
    // Silently fail if Rockpile app is not running
  });

  if (ROCKPILE_HOST) {
    // TCP mode: connect to remote Rockpile over network
    client.connect(ROCKPILE_PORT, ROCKPILE_HOST, onConnect);
  } else {
    // Unix socket mode: local same-machine
    client.connect(SOCKET_PATH, onConnect);
  }
}

export default function rockpilePlugin(api: PluginApi): void {
  // Log connection mode on load
  if (ROCKPILE_HOST) {
    console.log(`[rockpile] TCP mode → ${ROCKPILE_HOST}:${ROCKPILE_PORT}`);
  } else {
    console.log(`[rockpile] Unix socket mode → ${SOCKET_PATH}`);
  }

  // Agent lifecycle
  api.registerHook("before_agent_start", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "AgentStart",
      status: "working",
      ts: Date.now(),
    });
  });

  api.registerHook("llm_input", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "LLMInput",
      status: "thinking",
      user_prompt: ctx.data?.prompt,
      ts: Date.now(),
    });
  });

  api.registerHook("llm_output", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "LLMOutput",
      status: "working",
      ts: Date.now(),
    });
  });

  // Tool events
  api.registerHook("before_tool_call", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "ToolCall",
      status: "working",
      tool: ctx.data?.toolName,
      ts: Date.now(),
    });
  });

  api.registerHook("after_tool_call", async (ctx) => {
    const hasError = ctx.data?.error != null;
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "ToolResult",
      status: hasError ? "error" : "working",
      tool: ctx.data?.toolName,
      error: hasError ? String(ctx.data!.error) : undefined,
      ts: Date.now(),
    });
  });

  // Session lifecycle
  api.registerHook("agent_end", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "AgentEnd",
      status: "idle",
      ts: Date.now(),
    });
  });

  api.registerHook("session_start", async (ctx) => {
    sendEvent({
      session_id: ctx.sessionKey || "default",
      event: "SessionStart",
      status: "idle",
      ts: Date.now(),
    });
  });

  api.registerHook("session_end", async (ctx) => {
    sendEvent({
      session_id: ctx.sessionKey || "default",
      event: "SessionEnd",
      status: "ended",
      ts: Date.now(),
    });
  });

  // Subagent events
  api.registerHook("subagent_spawned", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "SubagentSpawned",
      status: "working",
      ts: Date.now(),
    });
  });

  api.registerHook("subagent_ended", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "SubagentEnded",
      status: "idle",
      ts: Date.now(),
    });
  });

  // Compaction
  api.registerHook("before_compaction", async (ctx) => {
    sendEvent({
      session_id: ctx.runId || ctx.sessionKey || "default",
      event: "Compaction",
      status: "compacting",
      ts: Date.now(),
    });
  });

  // Message events
  api.registerHook("message_received", async (ctx) => {
    sendEvent({
      session_id: ctx.sessionKey || "default",
      event: "MessageReceived",
      status: "working",
      user_prompt: ctx.data?.text,
      ts: Date.now(),
    });
  });
}
