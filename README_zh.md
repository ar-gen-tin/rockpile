<div align="center">

**🇨🇳 中文** | [🇺🇸 English](README.md) | [🇯🇵 日本語](README_ja.md)

# <img src="docs/images/crawfish.png" width="36" height="36" alt="Rockpile" style="vertical-align: middle;" /> Rockpile

**macOS Notch 栏像素伴侣 — 实时展示 AI Agent 工作状态**

[![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.5-brightgreen)](https://github.com/ar-gen-tin/rockpile/releases)

[![GitHub Stars](https://img.shields.io/github/stars/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/issues)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ar-gen-tin/rockpile?style=flat-square&logo=github)](https://github.com/ar-gen-tin/rockpile/commits/main)

<br>

<!--
  将截图放入 docs/images/ 目录，取消下方注释
  Put your screenshots in docs/images/ and uncomment below
-->
<!-- ![Rockpile Screenshot](docs/images/screenshot-hero.png) -->

</div>

---

## 什么是 Rockpile？

Rockpile 是一个住在 MacBook **Notch 刘海区域**的像素小龙虾伴侣。它通过 Socket 连接你的 AI Agent（Claude Code 等），将 Agent 的思考、编码、等待、出错等状态，实时映射为小龙虾的动画、情绪和水下环境变化。

- 🧠 **Agent 思考时**，小龙虾低头沉思
- 🔨 **调用工具时**，小龙虾忙碌工作
- ⏳ **等待输入时**，小龙虾左右张望
- 💀 **Token 耗尽时**，水变浑浊，小龙虾翻肚……

> 刘海里的一只虾。

---

## 特性

### 🎮 双生物系统

两只像素生物同缸共居，各自追踪不同的 AI 数据源：

| 生物 | 角色 | 数据来源 |
|------|------|---------|
| 🦀 **寄居蟹** | 本机 AI | Unix Socket / 本地文件 |
| 🦞 **小龙虾** | 远程 AI | TCP / Gateway WebSocket |

### 🌊 沉浸式水下场景

- 像素风海底 — 沙地、海草摇曳、气泡升腾、光线穿透
- O₂ 联动 — Token 消耗越多，水越浑浊，气泡越少
- 互动粒子 — 两只生物闲暇时会碰面玩耍，绽放星星和水花

### 📊 O₂ 氧气瓶（Token 用量表）

Street Fighter 风格像素血条，直观映射 Token 消耗：

| 氧气 % | 颜色 | 水面效果 |
|--------|------|---------|
| 100–60% | 🟢 绿 | 清澈海水，气泡正常 |
| 60–30% | 🟡 黄 | 水色偏暗，气泡减少 |
| 30–10% | 🔴 红闪 | 浑浊死水，光线微弱 |
| 0% | 💀 K.O. | 翻肚嗝屁 |

支持两种模式：
- **Claude 限额** — 读取 `stats-cache.json`，追踪每日订阅配额
- **按量付费** — 支持 Anthropic / xAI / OpenAI API 真实用量查询

### 🔌 三种运行模式

```
模式 A：本机          模式 B：双机远程            模式 C：服务端
┌──────────┐     ┌──────────┐  ┌──────────┐    ┌──────────┐
│ Agent    │     │ Agent    │  │ Rockpile │    │ Agent    │
│ Rockpile │     │ Rockpile │  │ 🦞 Notch │    │ Rockpile │
│ 🦞 Notch │     │ (无UI)   │  │ (监控端) │    │ (无UI)   │
└──────────┘     └────┬─────┘  └────┬─────┘    └──────────┘
  Unix Socket         TCP:18790     │              Gateway
                      ────────────▶ │              WebSocket
```

| 模式 | 比喻 | 适用场景 |
|------|------|---------|
| **本机** | 养殖龙虾 🏠 | Agent 和 App 在同一台 Mac |
| **监控端** | 鱼缸 🐟 | MacBook 显示远程 Mac Mini 的 Agent 状态 |
| **服务端** | 野生龙虾 🌊 | Mac Mini 运行 Agent，发送事件给监控端 |

### 🎭 7 种状态 × 4 种情绪

| 状态 | 触发 | 情绪变体 |
|------|------|---------|
| 💤 空闲 | Agent 完成任务 | 😐 😊 😢 😠 |
| 🧠 思考 | LLM 推理中 | 😐 😊 |
| 🔨 工作 | 调用工具/生成代码 | 😐 😊 😢 |
| ⏳ 等待 | 等待用户输入 | 😐 😢 |
| ❌ 出错 | 工具调用失败 | 😐 😢 |
| 🌀 压缩 | 上下文压缩中 | 😐 😊 |
| 😴 休眠 | 5分钟无活动 | 😐 😊 |

情绪由 Claude Haiku 实时分析用户消息语义，60 秒自然衰减。

### 🤝 互动系统

| 操作 | 效果 |
|------|------|
| 单击 | 根据状态反应（跳跃+文字） |
| 双击 | 爱心特效 |
| 长按 | 信息卡片 |
| 右键 | 喂食（+O₂） |

两只生物闲暇时会自动互动 — 碰撞弹开、绕圈追逐、钳子碰拳、并排摇摆。

### 📡 Gateway 双向通信

- WebSocket 连接远程 Agent（`ws://<host>:18789`）
- 实时获取远程会话、Token 明细、健康状态
- **反向指令** — 从 Notch 直接发消息给远端 Agent
- 自动重连（指数退避 1s → 30s）
- Token 认证（HMAC-SHA256）

### 🐾 会话足迹

会话结束后自动保存记录，展示：
- 时间戳（智能格式：今天 `14:32` / 昨天 `昨天 14:32` / `3/8 14:32`）
- Token 消耗量（`1.2K` / `2.1M`）
- 工具调用摘要（`bash·edit·grep +2`）
- 可展开的 Token 明细（输入/输出/缓存读/缓存写）

### 🌏 三语支持

- 🇨🇳 中文
- 🇺🇸 English
- 🇯🇵 日本語

---

## 📈 项目统计

| 指标 | 数据 |
|------|------|
| **语言** | Swift 6.0 (100%) |
| **源文件** | 63 个 Swift 文件 |
| **代码行数** | ~12,600+ |
| **精灵资源** | 34 套（41 张图片） |
| **模块** | Core (6) · Models (9) · Services (19) · Views (22) · Window (5) |
| **多语言** | 🇨🇳 中文 · 🇺🇸 English · 🇯🇵 日本語 |
| **最低版本** | macOS 15.0 Sequoia |

---

## 系统要求

| 项目 | 要求 |
|------|------|
| **操作系统** | macOS 15.0 (Sequoia) 或更高 |
| **硬件** | 带 Notch 的 MacBook（2021+） |
| **Xcode** | 16.0+（从源码编译时） |
| **XcodeGen** | `brew install xcodegen` |

---

## 安装

### 方式 1：DMG 安装包（推荐）

从 [Releases](https://github.com/ar-gen-tin/rockpile/releases) 下载最新版 `.dmg`，拖入 Applications 即可。

> 已签名 + Apple 公证，双击即开，无需解除安全限制。

### 方式 2：从源码编译

```bash
# 克隆项目
git clone https://github.com/ar-gen-tin/rockpile.git
cd rockpile

# 安装构建工具
brew install xcodegen

# 生成 Xcode 项目 & 编译
xcodegen generate
xcodebuild -project Rockpile.xcodeproj \
  -scheme Rockpile \
  -configuration Release \
  build

# 或直接在 Xcode 中打开
open Rockpile.xcodeproj   # Cmd+R 运行
```

### 方式 3：签名发布构建

```bash
# 编译 + 签名 + DMG
bash build-release.sh

# 编译 + 签名 + DMG + Apple 公证
bash build-release.sh notarize
```

产物位于 `dist/Rockpile-v{version}.dmg`。

---

## 快速开始

### 1. 首次启动

打开 Rockpile，引导向导自动出现：

1. **选择语言** — 中文 / English / 日本語
2. **选择模式** — 本机 / 监控端 / 服务端
3. **配置 O₂** — AI 提供商、氧气瓶容量、Admin Key（可选）
4. **安装插件** — 自动生成 Hook 插件到 `~/.rockpile/plugins/rockpile/`

### 2. 开始使用

- 小龙虾出现在 Notch 旁 — 实时反映 Agent 状态
- **悬停/点击 Notch** — 展开面板，查看活动日志、O₂ 用量、会话足迹
- **菜单栏图标** — 快捷查看状态、配对码、设置

### 3. 远程配对（双机模式）

```
MacBook（监控端）                    Mac Mini（服务端）
1. 选择"监控端"模式                  1. 选择"服务端"模式
2. 屏幕显示配对码: 1HG-E15W    →    2. 输入配对码
3. 🦞 开始响应远程事件               3. 插件自动安装，重启 Agent
```

配对码 = IP 地址的 Base-36 编码（如 `192.168.1.100` → `1HG-E15W`）

---

## 架构

```
Claude Code Plugin (JS)
    ↓ Unix Socket / TCP:18790
SocketServer (BSD Socket, DispatchSource)
    ↓ HookEvent JSON
StateMachine (@MainActor, @Observable)
    ↓ 状态路由
SessionStore → SessionData[] → ClawState / EmotionState / TokenTracker
    ↓ SwiftUI 响应式
NotchContentView → PondView (水下场景) + ExpandedPanelView (信息面板)

Gateway WebSocket (ws://<host>:18789)
    ↓ 双向通信
GatewayClient → GatewayDashboard (health/status/sessions)
    ↓ 反向指令
CommandSender → chat.send → Remote Agent
```

### 技术栈

| 项目 | 技术 |
|------|------|
| 语言 | Swift 6.0（strict concurrency） |
| UI | SwiftUI + AppKit |
| 状态管理 | @Observable + @MainActor |
| 网络 | BSD Socket + URLSession WebSocket |
| 动画 | TimelineView + Canvas（无 Timer 泄漏） |
| 持久化 | UserDefaults + Keychain + 原子文件写入 |
| 构建 | XcodeGen + xcodebuild |
| 签名 | Developer ID + Hardened Runtime + 公证 |

### 项目结构

```
Rockpile/
├── Core/             # 设置、本地化、设计系统、启动项
├── Models/           # 状态枚举、情绪、会话数据、Token 追踪
├── Services/         # Socket 服务、Gateway、情感分析、插件管理
├── Views/            # 水下场景、精灵动画、面板、引导向导
├── Window/           # Notch 窗口、形状、命中测试
├── Assets.xcassets/  # 38 组精灵图（7状态 × 2-3情绪 × 2生物）
├── AppDelegate.swift # 生命周期 & 模式路由
└── RockpileApp.swift # @main 入口
```

### 通信协议

| 协议 | 端口/路径 | 用途 |
|------|----------|------|
| Unix Socket | `/tmp/rockpile.sock` | 本机模式事件传输 |
| TCP | `18790` | 远程模式事件传输 |
| HTTP | `18790 /health` | 健康检查 |
| WebSocket | `ws://:18789` | Gateway 双向通信 |

---

## 路线图

- [x] v0.1 — 基础版本：3种模式、7种状态、O₂系统、引导向导
- [x] v1.0 — 品牌重命名 ClawEMO → Rockpile
- [x] v1.1 — 会话历史（足迹）、版本更新流程
- [x] v1.2 — 足迹系统、原子写入持久化
- [x] v1.3 — Gateway WebSocket、反向指令、远程活动追踪
- [x] v2.0 — 双生物系统、Token API 监控、三语 i18n
- [ ] v2.5 — 拖拽喂食、物理急停、深度养成
- [ ] v3.0 — 局域网串门、团队排行、共享鱼缸

完整路线图见 [ROADMAP.md](docs/ROADMAP.md)。

---

## 文档

| 文档 | 说明 |
|------|------|
| [INSTALL.md](INSTALL.md) | 安装指南（三种模式详细步骤） |
| [DEVLOG.md](DEVLOG.md) | 开发记录（架构、版本历史、技术要点） |
| [ROADMAP.md](docs/ROADMAP.md) | 产品路线图 |

---

## 构建 & 发布

```bash
# 开发构建
xcodegen generate && xcodebuild -project Rockpile.xcodeproj -scheme Rockpile

# 签名 + DMG
bash build-release.sh

# 签名 + DMG + Apple 公证
bash build-release.sh notarize

# 部署到本机 + Mac Mini
bash deploy-to-mini.sh build
```

---

## 致谢

- 像素小龙虾精灵由 AI 生成并手工调整
- 灵感来自 [Notchi](https://github.com/sk-ruban/notchi)、[Star Office UI](https://github.com/ringhyacinth/Star-Office-UI) 等优秀的 macOS Notch 伴侣项目
- 使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理项目配置
- 使用 [create-dmg](https://github.com/create-dmg/create-dmg) 打包安装镜像

---

## 许可证

[MIT License](LICENSE) — 自由使用、修改和分发。

精灵图资源仅供本项目使用，不包含在 MIT 许可范围内。

---

<div align="center">

**🦞 刘海里的一只虾**

[下载](https://github.com/ar-gen-tin/rockpile/releases) · [安装指南](INSTALL.md) · [开发记录](DEVLOG.md) · [路线图](docs/ROADMAP.md)

</div>
