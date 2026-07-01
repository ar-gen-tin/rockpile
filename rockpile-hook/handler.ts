import http from "http";

// ── Configuration ───────────────────────────────────────────────
// Set ROCKPILE_HOST to the IP of the Mac running Rockpile.
//
// Examples:
//   export ROCKPILE_HOST=192.168.1.100   -> POST to http://192.168.1.100:18790
//   export ROCKPILE_HOST=localhost        -> POST to http://localhost:18790
//
const ROCKPILE_HOST = process.env.ROCKPILE_HOST || "localhost";
const ROCKPILE_PORT = parseInt(process.env.ROCKPILE_PORT || "18790", 10);

// ── Event mapping ───────────────────────────────────────────────

interface RockpileEvent {
  type: string;        // 'command' | 'session' | 'message' | 'agent' | 'gateway'
  action: string;      // 'received' | 'sent' | 'new' | 'stop' etc.
  sessionKey?: string;
  timestamp?: Date;
  context?: Record<string, any>;
  messages?: string[];
}

interface RockpilePayload {
  session_id: string;
  event: string;
  status: string;
  ts: number;
  user_prompt?: string;
  tool?: string;
  error?: string;
}

function mapEvent(event: RockpileEvent): RockpilePayload | null {
  const sessionId = event.sessionKey || event.context?.sessionId || "default";
  const ts = Date.now();

  const eventKey = `${event.type}:${event.action}`;

  switch (eventKey) {
    case "message:received":
      return {
        session_id: sessionId,
        event: "MessageReceived",
        status: "thinking",
        ts,
        user_prompt:
          event.context?.content ||
          event.context?.body ||
          event.context?.bodyForAgent,
      };

    case "message:preprocessed":
      return {
        session_id: sessionId,
        event: "LLMInput",
        status: "thinking",
        ts,
        user_prompt:
          event.context?.bodyForAgent ||
          event.context?.body ||
          event.context?.content,
      };

    case "message:sent":
      return {
        session_id: sessionId,
        event: "AgentEnd",
        status: "idle",
        ts,
      };

    case "session:compact:before":
      return {
        session_id: sessionId,
        event: "Compaction",
        status: "compacting",
        ts,
      };

    case "session:compact:after":
      return {
        session_id: sessionId,
        event: "LLMOutput",
        status: "working",
        ts,
      };

    case "command:new":
      return {
        session_id: sessionId,
        event: "SessionStart",
        status: "idle",
        ts,
      };

    case "command:stop":
      return {
        session_id: sessionId,
        event: "SessionEnd",
        status: "ended",
        ts,
      };

    case "command:reset":
      return {
        session_id: sessionId,
        event: "SessionEnd",
        status: "ended",
        ts,
      };

    case "gateway:startup":
      return {
        session_id: "system",
        event: "SessionStart",
        status: "idle",
        ts,
      };

    default:
      return null;
  }
}

// ── HTTP POST sender ────────────────────────────────────────────

function sendToRockpile(payload: RockpilePayload): void {
  const data = JSON.stringify(payload);

  const req = http.request(
    {
      hostname: ROCKPILE_HOST,
      port: ROCKPILE_PORT,
      path: "/hook",
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(data),
      },
      timeout: 3000,
    },
    (_res) => {
      // Response received, all good
    }
  );

  req.on("error", () => {
    // Silently fail if Rockpile app is not running
  });

  req.on("timeout", () => {
    req.destroy();
  });

  req.write(data);
  req.end();
}

// ── Hook handler ────────────────────────────────────────────────

const handler = async (event: RockpileEvent): Promise<void> => {
  const payload = mapEvent(event);
  if (payload) {
    sendToRockpile(payload);
  }
};

export default handler;
