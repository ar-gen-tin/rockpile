# Rockpile 开发记录

> 版本: v2.0.5 | 更新: 2026-03-11

---

## 项目概览

Rockpile 是 macOS Notch 栏小龙虾伴侣应用，通过动画像素小龙虾实时展示 AI Agent（Rockpile）的工作状态。

- **代码量**: ~12,600 行 Swift，63 个源文件
- **框架**: SwiftUI + Swift 6 严格并发
- **系统要求**: macOS 15.0 (Sequoia)+
- **构建工具**: XcodeGen + xcodebuild
- **部署**: 本机 + Mac Mini (Tailscale)

---

## 架构

### 三种运行模式

| 模式 | 比喻 | 说明 |
|------|------|------|
| 本机模式 | 养殖龙虾 | Rockpile Agent + Rockpile App 同一台 Mac，Unix Socket 通信 |
| 控制端 | 鱼缸 | 本机显示远程 Rockpile 状态，TCP:18790 接收事件 |
| 服务端 | 野生龙虾 | 运行 Rockpile Agent，发送事件给远端鱼缸，无 Notch UI |

### 核心流程

```
Rockpile Plugin (JS)
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
CommandSender → chat.send → Rockpile Agent
```

### 文件结构

```
Rockpile/
├── Core/           AppSettings, DesignTokens, EventMonitor, ScreenSelector
├── Models/         ClawState, EmotionState, GatewayModels, HookEvent,
│                   SessionData, SessionHistory, TokenTracker
├── Services/       CommandSender, EmotionAnalyzer, EventLogger, GatewayClient,
│                   GatewayDashboard, PanelManager, PluginInstaller,
│                   RemoteActivityTracker, SessionStore, SetupManager,
│                   SocketServer, SoundService, StateMachine, StatusBarController
├── Views/          ActivityBadgeView, BobAnimation, BubbleView, CrawfishSpriteView,
│                   DashboardPulseView, DecorationView, ExpandedPanelView,
│                   FoodParticleView, GhostSpriteView, HistoryRowView,
│                   OnboardingView, OxygenBarView, PondView, SessionListView,
│                   SplashParticleView, SpotlightInputView, SpriteInfoCardView,
│                   SpriteSheetView, TransitionFXView, WaterSurfaceView
├── Window/         NotchPanel, NotchContentView, NotchShape, NotchHitTestView, NSScreen+Notch
└── Assets.xcassets 17 组精灵图 (7状态 × 2-3情绪)
```

---

## 版本历史

### v2.0.5 (2026-03-11) — 双生物 + Token API + i18n + 签名发布

#### 双生物系统
- 寄居蟹（本机 AI）+ 小龙虾（远程 AI）同缸共居
- 各自独立追踪不同 AI 数据源的 O₂ 用量
- 双 O₂ 条并排显示，左蟹右虾
- 闲暇互动：碰撞弹开、绕圈追逐、钳子碰拳、并排摇摆

#### Token 用量 API 监控 (`UsageQueryService.swift`)
- 支持 Anthropic / xAI / OpenAI 管理 API 真实用量查询
- Claude 订阅模式直接读取 `stats-cache.json`（30s 轮询）
- xAI 余额显示（美元）
- 错误指数退避（1→2→4→8→15 分钟）
- Admin Key 安全存储（Keychain）

#### 三语国际化 (`L10n.swift`)
- 完整三语支持：中文 / English / 日本語
- 891 行本地化字符串
- 所有 UI 文字、菜单项、引导向导、反应文案全部本地化
- 运行时切换，Notification 驱动刷新

#### AI 提供商自动检测 (`AIProviderDetector.swift`)
- 自动检测本机 AI 提供商（Claude 目录、环境变量、配置文件）
- 支持：Claude (订阅/API)、xAI、OpenAI、Google Gemini、DeepSeek
- OnboardingView 按量付费模式：Admin Key 输入 + 测试连接

#### 代码签名 & DMG 发布
- `build-release.sh`: 编译 → 签名 → DMG → 公证一键流程
- Developer ID Application 签名 + Hardened Runtime
- Apple 公证 + Staple 票据嵌入
- `project.yml` 分离 Debug/Release 签名配置

#### 系统功能
- 开机启动（SMAppService）— 设置面板 + 菜单栏双入口
- 菜单栏全面本地化（从硬编码中文改为 L10n 驱动）
- SpotlightInputView 增加 🦞 图标指示发送目标

#### 文件变更统计
- **新增**: InteractionCoordinator, InteractionFXView, UsageQueryService, AdminKeyManager, AIProviderDetector, HermitCrabSpriteView, CompactOxygenBarView, DualSourceCardView, LaunchAtLogin 等 15+ 文件
- **重写**: OnboardingView（双生物配置）, PondView（双生物场景）
- **净增代码**: ~3,700 行

---

### v1.3.0 (2026-03-10) — Gateway 双向通信

#### Gateway WebSocket 客户端 (`GatewayClient.swift`)
- 连接流程：WebSocket → connect.challenge (nonce) → connect (token auth) → hello-ok
- 指数退避自动重连（1s → 2s → 4s … 最大 30s）
- 30s WebSocket ping keepalive
- 请求-响应模型：pendingRequests + 30s 超时
- Token 解析：本机读 `~/.rockpile/rockpile.json`，远程用 Keychain
- AppSettings 新增 `gatewayPort` (18789) + `gatewayToken` (Keychain 存储)
- 连接状态追踪：disconnected / connecting / authenticating / connected

#### Gateway Dashboard (`GatewayDashboard.swift` + `GatewayModels.swift`)
- 系统级快照：`GatewaySnapshot` (会话数、当前模型、健康状态、运行时间)
- 会话明细：`SessionDetail` (per-session token breakdown: input/output/cache)
- 三路并行拉取：`health` + `status` + `sessions.list`
- 60 秒缓存 TTL，足迹页打开时按需刷新
- 仪表脉冲条 `DashboardPulseView`：连接时 `🟢 3会话 · grok-4`，断开时 `近 N 次`

#### 反向指令发送 (`CommandSender.swift`)
- 通过 Gateway WebSocket `chat.send` 方法发送消息给 Rockpile Agent
- Gateway 未连接时队列 1 条消息（TTL 30s，自动过期）
- Gateway 连接后自动 flush 队列
- 会话 key 自动解析（从 hello-ok snapshot 获取）
- 状态反馈：idle / sending / sent / queued / noSession / error

#### SpotlightInputView 输入框 (`SpotlightInputView.swift`)
- 展开面板底部常驻输入框
- Enter 发送，Escape 关闭并归还焦点
- 发送状态反馈条（绿色已发送 / 黄色等待连接 / 红色错误）

#### 远程活动追踪 (`RemoteActivityTracker.swift` + `ActivityBadgeView.swift`)
- Gateway 推送事件路由（Telegram / WhatsApp / Discord / Slack / Web 频道）
- 两阶段显示：折叠态 header 📱 +N 指示器 → 展开态小龙虾气泡 4s 消失
- 0.5s 防抖合并同会话连续事件

#### 足迹可展开明细 (`HistoryRowView.swift`)
- 点击足迹行展开 token 明细：输入 / 输出 / 缓存读 / 缓存写
- `SessionRecord` 新增 Optional 字段：inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, modelName
- 旧记录向后兼容（nil → "无详细数据"）

#### 交通灯连接指示 (`NotchContentView.swift`)
- 展开面板左上角 macOS 风格红黄绿状态灯
- 绿 = Gateway 已连接 / 有活跃会话
- 黄 = 连接中 / 认证中 / 发送中 / 排队中
- 红 = 全部断开

#### Host 模式 Gateway 自动连接
- `AppDelegate.launchHostOnlyMode()` 启动时自动 `GatewayClient.shared.connect()`
- 服务端无 Notch UI，但通过 Gateway 参与双向通信

#### 文件变更统计
- **新增 8 个文件**: GatewayClient.swift, GatewayDashboard.swift, GatewayModels.swift, CommandSender.swift, RemoteActivityTracker.swift, ActivityBadgeView.swift, DashboardPulseView.swift, HistoryRowView.swift
- **修改 8 个文件**: AppDelegate.swift, AppSettings.swift, NotchContentView.swift, ExpandedPanelView.swift, PondView.swift, PanelManager.swift, SessionHistory.swift, StatusBarController.swift
- **净增代码**: ~1,900 行

---

### v1.2.0 — 足迹系统 + 会话历史

#### SessionHistory 持久化 (`SessionHistory.swift`)
- 会话结束时自动保存足迹到 `~/Library/Application Support/Rockpile/session-history.json`
- 原子写入（temp → backup → rename），崩溃安全
- 加载时自动尝试 .bak 备份恢复
- 最多保留 100 条记录，按结束时间倒序
- 过滤无意义会话（无 token + 无工具 + 少于 3 条活动）

#### SessionRecord 数据模型
- 记录：sessionId, 起止时间, toolCallCount, totalTokens, toolNames
- 智能时间显示：今天 → "14:32"，昨天 → "昨天 14:32"，更早 → "3/8 14:32"
- 时长格式化："2分15秒" / "45秒" / "<1秒"
- 工具摘要："bash·edit·grep +2"

#### 足迹视图 (ExpandedPanelView 空闲态)
- 无活跃会话时显示 🐾 足迹列表
- 常驻 O₂ 氧气条（即使无会话也可见）
- "等待连接" 空状态引导

---

### v1.1.0 — 引导优化 + 版本更新

#### 版本更新流程
- `AppSettings.needsOnboarding` 检测版本变化
- 版本更新时 "保持设置" 一键跳过引导
- `versionNotes` 变更摘要展示
- `setupCompletedVersion` 记录完成引导时的版本

#### StatusBarController 重构
- NSMenuDelegate 驱动菜单构建（取代 Timer 轮询）
- 展示：当前状态、活跃会话数、O₂ 百分比、配对码、IP
- 底部显示 `Rockpile v{version}`

#### 菜单栏图标
- 从 idle_neutral 精灵表提取第一帧
- `isTemplate = true` 自动适配亮暗模式

---

### v1.0.0 — 品牌重命名

#### 全局重命名
- ClawEMO → **Rockpile**
- Openclaw → **Rockpile**
- Socket 路径: `/tmp/clawemo.sock` → `/tmp/rockpile.sock`
- Bundle ID: `com.clawemo.app` → `com.rockpile.app`
- 日志目录: `~/Library/Logs/ClawEMO` → `~/Library/Logs/Rockpile`
- 应用支持: `~/Library/Application Support/ClawEMO` → `~/Library/Application Support/Rockpile`
- 通知名称: `clawemoShould*` → `rockpileShould*`
- Keychain service: `com.clawemo.*` → `com.rockpile.*`

---

### v0.1.0 (2026-03-10) — 首个正式版本

#### 核心功能
- 3 步引导安装流程（选角色 → 配置+O₂ → 安装测试）
- 三种模式支持（本机/控制端/服务端）
- 配对码系统（IP → Base36 7位编码）
- Rockpile 插件自动生成与安装
- 版本更新时支持"保持设置"一键更新

#### 小龙虾系统
- 7 种状态动画（idle/thinking/working/waiting/error/compacting/sleeping）
- 情绪系统（Claude Haiku 分析 → 表情变化 → 60s 衰减）
- 互动系统：单击跳跃、双击爱心、长按信息卡、右键喂食
- 死亡动画：翻肚 + 去饱和 + 幽灵上升 + K.O. 闪烁
- 多会话支持：多只小龙虾同时游泳，哈希位置分配

#### 水下场景 (PondView)
- 海草摇摆动画（Canvas + TimelineView）
- 气泡系统：背景泡泡 + 嘴部呼吸泡泡
- 水面波浪效果
- 光线穿透效果
- O₂ 联动：低氧时水变浑浊、气泡减少、光线变暗
- 底部装饰：石头 + 可点击贝壳

#### O₂ 氧气瓶系统
- 像素血条样式（Street Fighter 风格）
- 双模式：Claude 配额制 / xAI-Google 按量付费
- 容量预设：500K / 1M / 2M / 5M tokens
- 颜色分级：绿(100-60%) → 黄(60-30%) → 红闪(30-10%) → K.O.(0%)

#### 展开面板
- 上 30%：水下场景（无文字覆盖）
- 下 70%：纯黑信息区
- 当前状态 + O₂ 条
- 活动日志（最近 5-10 条）
- 空闲时显示会话历史
- 设置面板：固定/静音/导出日志/重置

#### 网络通信
- Unix Socket: `/tmp/rockpile.sock`（本机模式）
- TCP: 端口 18790（远程模式）
- HTTP: POST /hook（事件）、POST /register（配对）、GET /health（健康检查）
- Content-Length 精确读取，5s 超时保护

#### 菜单栏
- 小龙虾剪影图标（模板图标，自动适配亮暗）
- 显示：当前状态、活跃会话数、O₂ 百分比
- 连接信息：模式、配对码、IP
- 操作：设置、导出日志、打开日志文件夹
- 底部显示版本号

---

## 优化记录 (v0.1.0)

### P0 — 关键修复

#### Socket 超时与数据丢失
- **问题**: 100ms 接收超时导致大 payload 被截断
- **修复**: 超时改为 5s；HTTP 请求用 Content-Length 精确读取 body；Raw JSON 读到连接关闭
- **文件**: `SocketServer.swift`

#### Timer 生命周期泄漏
- **问题**: SessionData.sleepTimer 在会话移除后仍在 RunLoop 中触发；StatusBarController.menuRefreshTimer 未存储引用
- **修复**: SessionData 增加 `cleanup()` 方法（Swift 6 不允许 @MainActor deinit）；SessionStore 在移除会话前调用 cleanup；StatusBarController 改为 NSMenuDelegate 按需构建
- **文件**: `SessionData.swift`, `SessionStore.swift`, `StatusBarController.swift`

#### 插件安装静默失败
- **问题**: 所有文件操作使用 `try?`，失败无日志
- **修复**: 全部改为 `do/catch` + logger.error + EventLogger 记录；增加安装后文件验证；TCP 插件增加 host 参数消毒；插件 JS 增加 3 次指数退避重试
- **文件**: `PluginInstaller.swift`

#### 会话历史损坏风险
- **问题**: 直接写入文件，崩溃时可能损坏
- **修复**: 原子写入（temp → backup → rename）；加载时尝试 .bak 备份恢复
- **文件**: `SessionHistory.swift`

### P1 — 重要改进

#### 日志轮转
- **之前**: 单文件无限增长
- **修复**: 3 文件轮转（.log → .log.1 → .log.2）
- **文件**: `EventLogger.swift`

#### 版本号管理
- **问题**: Info.plist 硬编码版本，build-pkg.sh 硬编码 "0.9"
- **修复**: Info.plist 使用 `$(MARKETING_VERSION)` 变量；build-pkg.sh 从 project.yml 读取版本
- **文件**: `Info.plist`, `build-pkg.sh`, `project.yml`

#### 部署脚本回滚
- **修复**: 远程解压后验证 .app + Info.plist 存在，失败时自动回滚到备份
- **文件**: `deploy-to-mini.sh`

#### AppDelegate 启动模式路由
- **Bug**: 启动时不检查 setupRole，host 模式也进 launchNotchMode() 画刘海
- **修复**: 增加 `AppSettings.setupRole == "host"` 检查，host 走 launchHostOnlyMode()
- **文件**: `AppDelegate.swift`

### P2 — 无障碍 & UX

#### VoiceOver 支持
- NotchContentView 头部按钮：固定/设置/关闭 增加 accessibilityLabel
- OxygenBarView：accessibilityElement + accessibilityValue（百分比/耗尽）
- **文件**: `NotchContentView.swift`, `OxygenBarView.swift`

#### ReduceMotion 支持
- CrawfishSpriteView：停止晃动和颤抖
- SeaweedStalk：停止摇摆（静态渲染）
- BubblesView：隐藏装饰性气泡
- BreathBubblesView：隐藏嘴部气泡
- UnderwaterSpriteView：禁用游泳、入场动画、状态切换弹跳
- **文件**: `CrawfishSpriteView.swift`, `PondView.swift`

---

## 版本号规则

- **project.yml** `MARKETING_VERSION` 是唯一版本来源
- Info.plist 通过 `$(MARKETING_VERSION)` 引用
- 修改版本后需 `rm -rf build` 再编译（增量构建缓存 plist）

| 类型 | 递增 | 示例 |
|------|------|------|
| 小修（bug/小功能/小调整） | +0.0.1 | 1.3.0 → 1.3.1 |
| 大改（新功能/重构） | +0.1.0 | 1.3.0 → 1.4.0 |

---

## 部署流程

```bash
# 完整编译 + 部署本机 + Mac Mini
bash deploy-to-mini.sh build

# 仅推送已编译的 .app
bash deploy-to-mini.sh

# 打 .pkg 安装包
bash build-pkg.sh

# 远程启动
ssh $MINI_USER@$MINI_HOST "open /Applications/Rockpile.app"
```

**远程**: Mac Mini via Tailscale（需配置 `MINI_USER` 和 `MINI_HOST` 环境变量）

---

## 技术要点

- **Swift 6 严格并发**: @MainActor 隔离 UI 类，deinit 不能访问隔离属性（用 cleanup() 替代）
- **Sendable 安全**: 捕获值类型进 Task 闭包，避免 var 数据竞争；GatewayResponse 用 Data 而非 [String: Any]
- **TimelineView**: 所有动画用 TimelineView 驱动，无 Timer 泄漏风险
- **Canvas**: 海草/气泡/粒子用 Canvas 绘制，避免大量 View 实例
- **BSD Socket**: 原生 socket/bind/listen/accept，DispatchSource 异步 I/O
- **URLSessionWebSocketTask**: Gateway 连接用系统 WebSocket，nonisolated receive loop 避免阻塞 MainActor
- **XcodeGen**: project.yml 管理所有构建配置，避免 .xcodeproj 冲突
- **Keychain**: Gateway token 用 Security.framework 存储，不进 UserDefaults
- **原子写入**: 会话历史 temp → backup → rename 三步写入，崩溃安全
