# Rockpile 安装指南

Rockpile 是 Rockpile 的 macOS Notch 伴侣应用，通过动画小龙虾精灵实时显示 AI Agent 的工作状态。

## 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- 带有 Notch 的 Mac（MacBook Pro 14"/16" 2021 及以上）
- Rockpile 已安装并可运行（至少在一台机器上）

## 不需要 Apple 开发者账号

**本地开发和测试完全不需要 Apple Developer Program 会员资格。**

| 场景 | 需要开发者账号？ | 说明 |
|------|:---:|------|
| Xcode 编译 & 本地运行 | **否** | 免费 Apple ID 即可 |
| 在自己的 Mac 上安装测试 | **否** | Xcode 自动签名 "Sign to Run Locally" |
| 发给朋友测试（Ad Hoc） | **否** | 拷贝 .app 文件即可，但需要在系统设置中允许 |
| 上架 Mac App Store | **是** | 需要 $99/年的开发者账号 |
| 公证 (Notarization) | **是** | 消除 "无法验证开发者" 弹窗 |

### 解除安全限制（无开发者账号时）

首次从外部来源打开 Rockpile 时，macOS 会阻止运行。解决方法：

```bash
# 方法 1：系统设置
# 系统设置 → 隐私与安全性 → 安全性 → 点击 "仍要打开"

# 方法 2：命令行移除隔离属性
xattr -cr /Applications/Rockpile.app
```

---

## 安装模式

Rockpile 支持三种安装模式，一个安装包适用于所有场景：

### 模式 A：本机模式 (Local)

**场景**：Rockpile 和 Rockpile 在同一台 Mac 上。

```
┌──────────── 同一台 Mac ────────────┐
│  Rockpile ──Unix Socket──▶ Rockpile │
│              /tmp/rockpile.sock     │
└────────────────────────────────────┘
```

**步骤**：
1. 在本机编译/安装 Rockpile
2. 首次启动，选择 **本机模式**
3. 自动安装插件到 `~/.rockpile/plugins/rockpile/`
4. 重启 Rockpile：`rockpile gateway restart`
5. 小龙虾出现在 Notch 区域

---

### 模式 B：远程监控（双机模式）

**场景**：Rockpile 运行在 Mac Mini（无屏幕），你想在 MacBook 的 Notch 上看到状态。

```
Mac Mini (服务端)                 MacBook (监控端)
┌──────────────────┐             ┌──────────────────┐
│ Rockpile         │             │ Rockpile          │
│ Rockpile 插件     │──TCP:18790──│ 小龙虾 Notch     │
│ (输入配对码)      │             │ (显示配对码)      │
└──────────────────┘             └──────────────────┘
```

**需要两台 Mac 各安装一次 Rockpile。**

#### 第 1 步：MacBook（监控端）

1. 安装 Rockpile
2. 首次启动，选择 **监控端**
3. 屏幕显示配对码（例如 `1HG-E15W`）
4. 记下配对码

#### 第 2 步：Mac Mini（服务端）

1. 安装 Rockpile
2. 首次启动，选择 **服务端**
3. 输入 MacBook 上的配对码
4. 自动安装 TCP 模式插件
5. 重启 Rockpile：`rockpile gateway restart`
6. 完成！MacBook 上的小龙虾开始响应

#### 配对码原理

配对码是 MacBook 的 IP 地址经 Base-36 编码后的 7 位字符串：
- `192.168.1.100` → `1HG-E15W`
- 输入配对码后自动解码为 IP 地址
- 插件通过 TCP:18790 发送事件到该 IP

---

## 编译安装

### 前置工具

```bash
# 安装 Xcode (从 Mac App Store 或 Apple 开发者网站)
# 安装 xcodegen
brew install xcodegen
```

### 编译步骤

```bash
# 1. 克隆项目
cd ~/Desktop
git clone <repo-url> Rockpile
cd Rockpile

# 2. 生成 Xcode 项目
xcodegen generate

# 3. 编译 (命令行)
xcodebuild -project Rockpile.xcodeproj \
  -scheme Rockpile \
  -configuration Release \
  build

# 4. 找到编译产物
open ~/Library/Developer/Xcode/DerivedData/Rockpile-*/Build/Products/Release/

# 或者直接在 Xcode 中打开编译：
# open Rockpile.xcodeproj
# Cmd+B 编译 / Cmd+R 运行
```

### 安装到 /Applications

```bash
# 找到 Release 版本的 .app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Rockpile-*/Build/Products/Release -name "Rockpile.app" -maxdepth 1)

# 复制到 Applications
cp -R "$APP_PATH" /Applications/Rockpile.app

# 移除隔离标记（如果需要）
xattr -cr /Applications/Rockpile.app
```

### 打包 .pkg 安装包

```bash
# 使用 build-pkg.sh 一键打包
bash build-pkg.sh

# 产物位于 dist/Rockpile-Installer.pkg
```

---

## 使用说明

### 首次启动

1. 打开 Rockpile
2. 引导向导自动出现，选择安装模式
3. 按提示完成配置
4. 引导完成后，Rockpile 自动切换到 Notch 模式

### 日常使用

- **小龙虾在 Notch 旁边**：显示当前 Rockpile 状态
- **点击 Notch 区域**：展开面板，查看详细活动日志
- **展开面板按钮**：
  - 📌 固定面板（不自动收起）
  - 🔊 静音/取消静音
  - ⚙️ 设置
  - ✕ 关闭面板

### 小龙虾状态

| 状态 | 动画 | 触发事件 |
|------|------|---------|
| 💤 空闲 | 放松站立 | Agent 完成任务 |
| 🧠 思考中 | 思考姿态 | LLM 正在推理 |
| 🔨 工作中 | 忙碌工作 | 调用工具/生成代码 |
| ⏳ 等待 | 左右张望 | 等待用户输入 |
| ❌ 出错 | 惊慌姿态 | 工具调用出错（3秒后恢复） |
| 🌀 压缩中 | 旋转 | 上下文压缩中 |
| 😴 休眠 | 闭眼 | 5分钟无活动 |

### 展开面板布局

展开面板分为上下两个区域：

```
┌─────────────────────────────┐
│        Notch 区域            │
├─────────────────────────────┤
│  🌊 池塘区 (30%)             │  ← 水下场景 + 小龙虾精灵
│  水草、气泡、光线              │     纯视觉，无文字覆盖
├─────────────────────────────┤
│  ■ 信息区 (70%) 黑色背景       │  ← 状态 + O₂ + 活动日志
│  ● 工作中           2 个会话   │
│  🫧 O₂  ████████░░░ 72%      │
│  ─────────────────────────   │
│  🧠 思考中...       20:15:32  │
│  🔧 bash            20:15:30  │
│  ✓  bash 完成       20:15:28  │
└─────────────────────────────┘
```

### 对话记录

会话结束后，记录自动保存到本地（最多 100 条），在无活跃会话时显示：

```
📋 对话记录                    3 条
─────────────────────────────────
14:32    1.2K    🔧 3          ← 今天的对话
昨天 09:15    850    🔧 5      ← 昨天的对话
3/8 16:40    2.1K              ← 更早的日期
```

每条记录显示：
- **发生时间** — 今天显示 `HH:mm`，昨天显示 `昨天 HH:mm`，更早显示 `M/d HH:mm`
- **Token 消耗量** — 格式化显示（如 `1.2K`、`2.1M`）
- **工具调用次数** — 🔧 图标 + 次数

记录存储路径：`~/Library/Application Support/Rockpile/session-history.json`

### 氧气瓶系统（O₂ Meter）

展开面板中会显示一个街霸风格的像素血条，代表 token 用量。

#### O₂ 模式

Rockpile 支持两种 O₂ 模式，在 **设置 → O₂ 氧气瓶** 中切换：

| 模式 | 数据来源 | 适用场景 |
|------|---------|---------|
| **Claude 限额** | `stats-cache.json` 当日累计用量 | Claude Pro/Free 用户，追踪每日配额 |
| **xAI / Google** | 累加每次请求的 token | 付费 API 用户（xAI Grok、Google Gemini 等），追踪会话消耗 |

#### 氧气等级效果

| 氧气 % | 血条颜色 | 水面效果 |
|--------|---------|---------|
| 100-60% | 🟢 绿色 | 气泡正常，清澈海水 |
| 60-30% | 🟡 黄色 | 气泡减少，水色偏暗 |
| 30-10% | 🔴 红色闪烁 | 水变浑浊，光线微弱 |
| 0% (429) | 💀 K.O. | 翻肚嗝屁，死水一潭 |

> **注意**：氧气条仅在收到包含 token 用量的事件时才会显示。

**容量设置**：展开面板 → ⚙️ 设置 → O₂ 氧气瓶 区域，可选择容量上限：
- 500K / 1M / 2M / 5M tokens（默认 1M）

### 情感系统

如果配置了 Anthropic API Key（设置页面），小龙虾会根据用户消息的情感变化表情：
- 😊 Happy：收到表扬或感谢
- 😢 Sad：用户沮丧或抱怨
- 😐 Neutral：普通指令（默认）

---

## 设置

### 重置引导

展开面板 → ⚙️ 设置 → **重置设置** → 重新运行引导向导

### 重新安装插件

展开面板 → ⚙️ 设置 → **重新安装插件**

### O₂ 模式切换

展开面板 → ⚙️ 设置 → **O₂ 氧气瓶** → 选择 `Claude 限额` 或 `xAI / Google`

### 调整氧气瓶容量

展开面板 → ⚙️ 设置 → **瓶容量** → 选择容量（500K / 1M / 2M / 5M tokens）

### 手动安装插件

如果引导向导失败，可以手动安装：

```bash
# 创建插件目录
mkdir -p ~/.rockpile/plugins/rockpile

# 创建 index.js (本机模式 - Unix Socket + O₂ token 追踪)
cat > ~/.rockpile/plugins/rockpile/index.js << 'PLUGIN'
const { Socket } = require("net");
const fs = require("fs");
const os = require("os");
const path = require("path");
const SOCKET_PATH = "/tmp/rockpile.sock";
const statsPath = path.join(os.homedir(), ".claude", "stats-cache.json");

function sendEvent(payload) {
  const client = new Socket();
  client.connect(SOCKET_PATH, () => {
    client.write(JSON.stringify(payload));
    client.end();
  });
  client.on("error", () => {});
}

// 读取 Claude Code 当日 token 累计用量
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

module.exports = function rockpilePlugin(api) {
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

      // 附加 token 用量数据（用于 O₂ 氧气瓶）
      if (usageHooks.has(hook)) {
        const usage = ctx.data?.usage;
        if (usage) {
          payload.input_tokens = usage.input_tokens;
          payload.output_tokens = usage.output_tokens;
          payload.cache_read_tokens = usage.cache_read_input_tokens;
          payload.cache_creation_tokens = usage.cache_creation_input_tokens;
        }
        payload.daily_tokens_used = readDailyTokens();
        if (ctx.data?.rateLimited || ctx.data?.status === 429) {
          payload.rate_limited = true;
        }
      }

      sendEvent(payload);
    });
  }
};
PLUGIN

# 创建 package.json
cat > ~/.rockpile/plugins/rockpile/package.json << 'PKG'
{
  "name": "rockpile-plugin",
  "version": "1.0.0",
  "main": "index.js",
  "description": "Rockpile notch companion plugin for Rockpile"
}
PKG

# 重启 Rockpile
rockpile gateway restart
```

### TCP 模式（远程监控）

将 `index.js` 中的连接改为 TCP：

```javascript
// 替换这两行：
// const SOCKET_PATH = "/tmp/rockpile.sock";
// client.connect(SOCKET_PATH, () => {

// 改为：
const ROCKPILE_HOST = "192.168.1.100"; // 监控 Mac 的 IP
const ROCKPILE_PORT = 18790;
client.connect(ROCKPILE_PORT, ROCKPILE_HOST, () => {
```

---

## 测试

### 测试脚本

项目附带 `rockpile-test.sh` 用于模拟 Rockpile 事件，验证 Rockpile 的全部功能。

```bash
# 用法（默认目标 IP 192.168.10.162）
bash rockpile-test.sh

# 指定目标 IP
bash rockpile-test.sh 192.168.1.100
```

测试脚本使用 **curl HTTP POST** 发送事件（比 nc 更可靠），包含以下测试：

| 测试 | 内容 |
|------|------|
| 连通性 | HTTP 健康检查 |
| 单会话流程 | SessionStart → LLMInput → LLMOutput → ToolCall → ToolResult → AgentEnd → SessionEnd |
| 多会话 | 同时创建 2 个会话，验证多只小龙虾 |
| O₂ 氧气瓶 | 逐步增加 token 用量（200K → 700K → 950K），观察颜色变化 |
| 错误恢复 | ToolResult 错误状态，验证 3 秒后自动恢复 |

---

## 网络要求

| 模式 | 网络需求 | 端口 |
|------|---------|------|
| 本机模式 | 无 | Unix Socket |
| 远程监控 | 同一局域网 | TCP 18790 |

**防火墙设置**（远程模式）：
- 监控端 Mac 需要允许 TCP 18790 入站连接
- macOS 会在首次运行时弹出防火墙确认，点击 **允许**

---

## 故障排查

### 小龙虾不动

1. 检查 Rockpile 是否在运行
2. 检查插件是否安装：`ls ~/.rockpile/plugins/rockpile/`
3. 重启 Rockpile：`rockpile gateway restart`
4. 查看日志：`log stream --predicate 'subsystem == "com.rockpile.app"' --level info`

### 远程连接失败

1. 确认两台 Mac 在同一网络
2. 检查防火墙是否放行 TCP 18790
3. 测试连通性：`curl -s http://<监控端IP>:18790/health`
4. 确认配对码正确（检查 IP 解码结果）

### 出现多只小龙虾

旧会话可能因网络问题未正确关闭。Rockpile 会自动清理：
- `sleeping` 状态的会话立即清理
- `idle` 状态超过 5 分钟自动清理

### 重新开始

```bash
# 清除所有设置
defaults delete com.rockpile.app

# 删除插件
rm -rf ~/.rockpile/plugins/rockpile

# 清除对话历史
rm -f ~/Library/Application\ Support/Rockpile/session-history.json

# 重新启动 Rockpile
```

---

## 项目结构

```
Rockpile/
├── Rockpile/
│   ├── RockpileApp.swift              # @main 入口
│   ├── AppDelegate.swift             # 窗口生命周期
│   ├── Core/
│   │   ├── AppSettings.swift         # UserDefaults 设置（含 O₂ 模式）
│   │   ├── DesignTokens.swift        # 设计令牌系统（间距/字体/颜色/透明度）
│   │   ├── EventMonitor.swift        # 全局事件监听
│   │   └── ScreenSelector.swift      # 多显示器支持
│   ├── Models/
│   │   ├── ClawState.swift           # 任务+情感状态枚举
│   │   ├── EmotionState.swift        # 情感积累与衰减
│   │   ├── HookEvent.swift           # 插件事件数据结构
│   │   ├── SessionData.swift         # 会话数据
│   │   ├── SessionHistory.swift      # 对话记录持久化
│   │   └── TokenTracker.swift        # Token 用量追踪（双模式 O₂）
│   ├── Services/
│   │   ├── EmotionAnalyzer.swift     # Claude Haiku 情感分析
│   │   ├── EventLogger.swift         # 事件日志记录
│   │   ├── PanelManager.swift        # 面板展开/收起
│   │   ├── PluginInstaller.swift     # 插件安装/重装
│   │   ├── SessionStore.swift        # 多会话管理 + 超时清理
│   │   ├── SetupManager.swift        # 引导向导逻辑
│   │   ├── SocketServer.swift        # Unix/TCP/HTTP 多协议服务器
│   │   ├── SoundService.swift        # 通知音效
│   │   ├── StateMachine.swift        # 事件→状态转换（中文活动日志）
│   │   └── StatusBarController.swift # 菜单栏控制
│   ├── Views/
│   │   ├── BobAnimation.swift        # 浮动动画
│   │   ├── CrawfishSpriteView.swift  # 小龙虾精灵（含嗝屁动画）
│   │   ├── ExpandedPanelView.swift   # 展开面板（活动/历史/设置）
│   │   ├── OnboardingView.swift      # 5步引导向导
│   │   ├── OxygenBarView.swift       # O₂ 像素血条（TimelineView 驱动）
│   │   ├── PondView.swift            # 水下池塘背景（含低氧效果）
│   │   ├── SessionListView.swift     # 会话列表
│   │   └── SpriteSheetView.swift     # 精灵帧动画
│   ├── Window/
│   │   ├── NotchContentView.swift    # Notch 根视图（池塘+信息区分层）
│   │   ├── NotchHitTestView.swift    # 点击穿透
│   │   ├── NotchPanel.swift          # NSPanel 无边框窗口
│   │   ├── NotchShape.swift          # Notch 形状路径
│   │   └── NSScreen+Notch.swift      # Notch 检测
│   ├── Assets.xcassets/              # 精灵图资源
│   ├── Info.plist
│   └── Rockpile.entitlements
├── rockpile-hook/                    # Rockpile Webhook 钩子
│   └── HOOK.md                       # 钩子事件映射文档
├── rockpile-test.sh                   # 测试脚本（curl HTTP POST）
├── build-pkg.sh                      # 打包 .pkg 脚本
├── project.yml                       # xcodegen 配置
└── INSTALL.md                        # 本文档
```

---

## 设计系统

Rockpile 使用统一的设计令牌系统 (`DesignTokens.swift`)，基于 Impeccable 设计原则：

### 间距（4pt 基准）

| Token | 值 | 用途 |
|-------|-----|------|
| `DS.Space.xxs` | 2pt | 行内微间距 |
| `DS.Space.xs` | 4pt | 紧凑元素间 |
| `DS.Space.sm` | 8pt | 组件内间距 |
| `DS.Space.md` | 12pt | 区块内边距 |
| `DS.Space.lg` | 16pt | 区块间距 |
| `DS.Space.xl` | 24pt | 大区域分隔 |

### 排版（5级层次）

| Token | 大小 | 用途 |
|-------|------|------|
| `DS.Font.caption` | 9pt mono | 时间戳、元数据 |
| `DS.Font.secondary` | 10pt | 次要信息、标签 |
| `DS.Font.body` | 11pt | 正文、活动详情 |
| `DS.Font.subhead` | 12pt medium | 副标题、状态 |
| `DS.Font.title` | 14pt semibold | 区块标题 |

### 透明度（5级语义）

| Token | 值 | 用途 |
|-------|-----|------|
| `DS.Opacity.primary` | 0.88 | 主要文字 |
| `DS.Opacity.secondary` | 0.60 | 次要文字 |
| `DS.Opacity.tertiary` | 0.38 | 时间戳、提示 |
| `DS.Opacity.muted` | 0.15 | 分隔线、边框 |
| `DS.Opacity.ghost` | 0.08 | 背景填充 |

---

## 技术规格

| 项目 | 值 |
|------|-----|
| 语言 | Swift 6.0 |
| UI 框架 | SwiftUI + AppKit |
| 并发模型 | Swift Concurrency (strict) |
| 最低系统 | macOS 15.0 |
| 通信协议 | Unix Socket + TCP + HTTP POST |
| 监听端口 | TCP 18790 |
| Socket 路径 | /tmp/rockpile.sock |
| 插件位置 | ~/.rockpile/plugins/rockpile/ |
| 设置存储 | UserDefaults (com.rockpile.app) |
| 对话记录 | ~/Library/Application Support/Rockpile/session-history.json |
| O₂ 模式 | Claude 限额 / xAI·Google 充值 |
| 设计系统 | DesignTokens.swift (4pt spacing, 5-level type scale) |

---

## 更新日志

### v1.1 (2026-03-09)

**布局重构**
- 展开面板分为独立的池塘区（30%）和信息区（70%黑色背景），文字不再覆盖池塘

**O₂ 双模式**
- 新增 O₂ 模式切换：Claude 限额预警 / xAI·Google 充值模式
- 设置面板中可自由切换模式和容量

**对话记录**
- 会话结束后自动保存记录到本地（最多 100 条）
- 显示绝对时间 + Token 消耗 + 工具调用次数
- 智能时间显示：今天 → `14:32`，昨天 → `昨天 14:32`，更早 → `3/8 14:32`

**UI 优化**
- 新增设计令牌系统（DesignTokens.swift），统一间距/字体/颜色/透明度
- 活动日志使用绝对时间（HH:mm:ss），不再有不停跳动的计时器
- 活动日志中文化（思考中、完成、工具出错等）
- OxygenBarView 改用 TimelineView 驱动闪烁，修复 Timer 泄漏
- 空状态改为友好的引导文案

**会话管理**
- 自动清理过期会话（sleeping 立即清理，idle 5 分钟超时）
- 单会话时小龙虾固定居中，不被 O₂ 条遮挡

**测试**
- 测试脚本重写为 curl HTTP POST，带重试机制，比 nc 更可靠
- 新增 O₂ 氧气瓶测试（200K → 700K → 950K 逐步加压）
