---
metadata:
  rockpile:
    events:
      - message:received
      - message:preprocessed
      - message:sent
      - session:compact:before
      - session:compact:after
      - command:new
      - command:stop
      - command:reset
      - gateway:startup
---

# Rockpile Webhook Hook

Rockpile 生命周期事件转发插件 — 将 Agent 状态变化通过 HTTP POST
发送给 Rockpile macOS 伴侣应用，驱动小龙虾动画和 O₂ 氧气条。

## 安装

插件由 Rockpile 首次启动时自动安装到 Rockpile 的 `hooks/` 目录。
也可在设置面板中点击"重新安装插件"手动触发。

安装路径：`~/.rockpile/hooks/rockpile-hook/`

## 配置

在运行 Rockpile 的机器上设置环境变量：

```bash
# 必填：运行 Rockpile 的 Mac 的 IP 地址
export ROCKPILE_HOST=192.168.1.100

# 可选：端口（默认 18790）
export ROCKPILE_PORT=18790
```

本机模式（Rockpile 和 Rockpile 在同一台 Mac 上）无需配置，
默认使用 `localhost:18790`。

## 通信协议

**HTTP POST** → `http://{ROCKPILE_HOST}:{ROCKPILE_PORT}/hook`

请求体 (JSON)：

```json
{
  "session_id": "abc123",
  "event": "LLMInput",
  "status": "thinking",
  "ts": 1710000000000,
  "user_prompt": "你好",
  "tool": "bash",
  "error": "File not found",
  "daily_tokens_used": 150000,
  "input_tokens": 1200,
  "output_tokens": 800
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `session_id` | string | 会话唯一标识 |
| `event` | string | 事件类型（见下表） |
| `status` | string | 目标状态：idle / thinking / working / compacting / ended |
| `ts` | number | Unix 时间戳 (ms) |
| `user_prompt` | string? | 用户输入内容（仅 MessageReceived / LLMInput） |
| `tool` | string? | 工具名称（仅 ToolCall / ToolResult） |
| `error` | string? | 错误信息（仅 ToolResult 出错时） |
| `daily_tokens_used` | int? | 每日累计 token（Claude 限额模式用） |
| `input_tokens` | int? | 本次请求输入 token |
| `output_tokens` | int? | 本次请求输出 token |

## 事件映射表

| Rockpile 事件 | Rockpile 事件 | 状态 | 小龙虾行为 |
|---------------|-------------|------|-----------|
| `message:received` | MessageReceived | thinking | 🤔 思考动画 |
| `message:preprocessed` | LLMInput | thinking | 🤔 保持思考 |
| `message:sent` | AgentEnd | idle | 😊 回到空闲 |
| `session:compact:before` | Compaction | compacting | 压缩中 |
| `session:compact:after` | LLMOutput | working | 💪 工作动画 |
| `command:new` | SessionStart | idle | 🦞 新建小龙虾 |
| `command:stop` | SessionEnd | ended | 💨 小龙虾消失 |
| `command:reset` | SessionEnd | ended | 💨 消失后重建 |
| `gateway:startup` | SessionStart | idle | 🦞 系统小龙虾 |

## Rockpile 端点

| 路径 | 方法 | 说明 |
|------|------|------|
| `/hook` | POST | 接收事件数据 |
| `/health` | GET | 健康检查，返回 `{"status":"ok"}` |
| `/` | POST | 同 `/hook`（兼容旧版） |

## 文件结构

```
rockpile-hook/
├── handler.ts      # Rockpile hook 入口，事件映射 + HTTP POST
├── package.json    # npm 包描述
└── HOOK.md         # 本文档
```

## 故障排查

**插件未触发**：
```bash
# 检查插件是否安装
ls ~/.rockpile/hooks/rockpile-hook/

# 检查 Rockpile 日志中是否加载了 hook
# 如未加载，在 Rockpile 设置中点"重新安装插件"
```

**事件未送达**：
```bash
# 在 Rockpile 所在的 Mac 上检查端口
curl http://localhost:18790/health

# 从远程机器检查连通性
curl http://192.168.1.100:18790/health

# 手动发送测试事件
curl -X POST http://localhost:18790/hook \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test","event":"SessionStart","status":"idle","ts":1710000000000}'
```

**查看 Rockpile 日志**：
```bash
tail -f ~/Library/Logs/Rockpile/rockpile.log
```
