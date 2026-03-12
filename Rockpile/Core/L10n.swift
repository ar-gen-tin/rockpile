import Foundation

// MARK: - Language

enum AppLanguage: String, CaseIterable, Sendable {
    case en, zh, ja

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        case .ja: return "日本語"
        }
    }

    var flag: String {
        switch self {
        case .en: return "🇺🇸"
        case .zh: return "🇨🇳"
        case .ja: return "🇯🇵"
        }
    }
}

// MARK: - L10n Engine

@MainActor
enum L10n {
    static var language: AppLanguage {
        AppLanguage(rawValue: AppSettings.appLanguage) ?? .en
    }

    /// Localized string lookup (falls back to English)
    static func s(_ key: String) -> String {
        let lang = language
        return allStrings[lang]?[key] ?? allStrings[.en]?[key] ?? key
    }

    /// Localized array lookup (for random reactions)
    static func a(_ key: String) -> [String] {
        let lang = language
        return allArrays[lang]?[key] ?? allArrays[.en]?[key] ?? [key]
    }

    /// Random element from localized array
    static func r(_ key: String) -> String {
        a(key).randomElement() ?? key
    }

    private static let allStrings: [AppLanguage: [String: String]] = [
        .en: enStrings, .zh: zhStrings, .ja: jaStrings,
    ]

    private static let allArrays: [AppLanguage: [String: [String]]] = [
        .en: enArrays, .zh: zhArrays, .ja: jaArrays,
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chinese (zh)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static let zhStrings: [String: String] = [
        // ── Creature ──
        "creature.hermitCrab": "寄居蟹",
        "creature.crawfish": "小龙虾",
        "creature.local": "本地",
        "creature.remote": "远程",

        // ── State ──
        "state.idle": "空闲",
        "state.thinking": "思考中…",
        "state.working": "工作中…",
        "state.sleeping": "休眠",
        "state.compacting": "压缩中…",
        "state.waiting": "等待中…",
        "state.error": "出错了",

        // ── O₂ ──
        "o2.normal": "正常",
        "o2.warning": "警告",
        "o2.danger": "危险",
        "o2.critical": "临界",
        "o2.ko": "K.O.",
        "o2.lowOxygen": "低氧",
        "o2.used": "已用",

        // ── Header ──
        "header.pin": "固定面板",
        "header.unpin": "取消固定",
        "header.settings": "设置",
        "header.close": "关闭面板",

        // ── Dashboard ──
        "dash.footprints": "足迹",
        "dash.activity": "活动",
        "dash.waiting": "等待连接",
        "dash.waitingDesc": "启动 Claude Code 或 Openclaw\n生物会在池塘里出现",
        "dash.model": "模型",
        "dash.input": "输入",
        "dash.output": "输出",
        "dash.cacheRead": "缓存读",
        "dash.cacheWrite": "缓存写",
        "dash.noDetail": "无详细数据",
        "dash.tapCollapse": "轻点折叠",
        "dash.tapDetail": "轻点查看详情",
        "dash.burnRate": "消耗率",
        "dash.eta": "预计耗尽",
        "dash.dailyProgress": "日进度",
        "dash.pace.ahead": "偏快",
        "dash.pace.onTrack": "正常",
        "dash.pace.behind": "偏慢",
        "dash.pace.idle": "待命",

        // ── Settings ──
        "settings.title": "设置",
        "settings.connection": "连接",
        "settings.mode": "模式",
        "settings.method": "方式",
        "settings.port": "端口",
        "settings.remoteHost": "远程主机",
        "settings.localIP": "本机",
        "settings.localO2": "本地 O₂ (寄居蟹)",
        "settings.remoteO2": "远程 O₂ (小龙虾)",
        "settings.dailyQuota": "日配额",
        "settings.auto": "tokens (自动)",
        "settings.claudeQuota": "Claude 配额",
        "settings.paidUsage": "按量付费",
        "settings.bottleCapacity": "瓶容量",
        "settings.detected": "检测到",
        "settings.actions": "操作",
        "settings.reinstallPlugin": "重新安装插件",
        "settings.resetSettings": "重置设置",
        "settings.reinstallDone": "✓ 插件已重新安装",
        "settings.reinstallNA": "控制端无需安装插件",
        "settings.language": "语言",
        "settings.startup": "启动",
        "settings.launchAtLogin": "开机自动启动",
        "settings.quit": "退出 Rockpile",

        // ── Menu ──
        "menu.activeSessions": "个活跃会话",
        "menu.depleted": "已耗尽",
        "menu.noSession": "暂无活跃会话",
        "menu.pairCode": "配对码",
        "menu.launchAtLogin": "开机启动",
        "menu.settings": "设置…",
        "menu.exportLog": "导出日志…",
        "menu.openLogFolder": "打开日志文件夹",
        "menu.quit": "退出 Rockpile",

        // ── Role ──
        "role.local": "本机模式",
        "role.monitor": "远程控制",
        "role.host": "Rockpile 服务端",
        "role.unknown": "未配置",

        // ── Input ──
        "input.placeholder": "发送指令... (↵)",
        "input.send": "发送指令",
        "input.sent": "已发送",
        "input.waitingConnection": "等待连接...",
        "input.noSession": "暂无活跃会话",

        // ── Time ──
        "time.second": "秒",
        "time.minute": "分",
        "time.hour": "时",
        "time.lessThan1s": "<1秒",
        "time.yesterday": "昨天",
        "time.noTools": "无工具",

        // ── Sprite Info ──
        "sprite.accessCrab": "寄居蟹",
        "sprite.accessCrawfish": "小龙虾",
        "sprite.accessHint": "轻点互动, 长按查看信息, 右键喂食",
        "sprite.noSession": "暂无活跃会话",

        // ── Feed ──
        "feed.overfed": "吃撑了…",
        "feed.feed": "喂食",
        "feed.cooldown": "冷却中",

        // ── Command ──
        "cmd.queued": "已有排队指令",
        "cmd.unknown": "未知错误",
        "cmd.failed": "发送失败",
        "cmd.expired": "指令已过期",
        "cmd.emergencyWIP": "急停功能开发中",

        // ── Version Notes ──
        "version.note1": "🐚 寄居蟹: 本地 Claude Code 专属生物",
        "version.note2": "🦞 双生态: 寄居蟹(本地) + 小龙虾(远程) 共存",
        "version.note3": "双 O₂ 进度条: 独立追踪本地/远程 token 消耗",
        "version.note4": "Dashboard 双源卡片: 分别显示本地和远程状态",
        "version.note5": "池塘分层: 寄居蟹底部爬行，小龙虾中上层游泳",

        // ── Provider ──
        "provider.claudeSub": "Claude 订阅",
        "provider.claudeAPI": "Anthropic API",
        "provider.openAI": "OpenAI",
        "provider.gemini": "Gemini",
        "provider.xAI": "xAI",
        "provider.deepSeek": "DeepSeek",
        "provider.unknown": "未知",
        "provider.dailyQuota": "日配额",
        "provider.payAsYouGo": "按量",

        // ── Onboarding ──
        "onboard.selectLanguage": "选择语言",
        "onboard.thisUpdate": "本次更新",
        "onboard.currentSettings": "当前设置",
        "onboard.roleQuestion": "这台 Mac 是什么角色？",
        "onboard.roleLocal": "本机使用",
        "onboard.roleLocalDesc": "寄居蟹(本地 Claude) + 可选远程小龙虾(Openclaw)",
        "onboard.roleMonitor": "鱼缸（控制端）",
        "onboard.roleMonitorDesc": "这台只有缸，输入配对码让龙虾从对面游过来",
        "onboard.roleHost": "服务端（无头模式）",
        "onboard.roleHostDesc": "只跑后台服务，配对后龙虾游进远处鱼缸",
        "onboard.localMode": "本机模式",
        "onboard.localCrab": "🐚 寄居蟹监控本地 Claude Code",
        "onboard.localCrawfish": "🦞 小龙虾监控远程 Openclaw（可选）",
        "onboard.foundClaude": "已找到 Claude",
        "onboard.autoInstall": "自动安装插件",
        "onboard.localComm": "本地通信",
        "onboard.unixSocket": "Unix Socket",
        "onboard.remoteConn": "远程连接",
        "onboard.gatewayWS": "Gateway WebSocket",
        "onboard.monitorMode": "鱼缸（控制端）",
        "onboard.enterCode": "输入配对码",
        "onboard.codeHint": "只保留字母数字，不区分大小写",
        "onboard.hostSide": "野生龙虾端",
        "onboard.hostMode": "野生龙虾（服务端）",
        "onboard.hostCodeHint": "把下面的配对码告诉鱼缸端（看小龙虾的那台 Mac）",
        "onboard.foundRockpile": "已找到 Rockpile",
        "onboard.notFoundRockpile": "没找到 Rockpile",
        "onboard.needInstall": "需要先安装 Rockpile 才能继续",
        "onboard.waitingTank": "等待鱼缸接入",
        "onboard.waitingTankDesc": "在鱼缸端（看小龙虾的那台 Mac）输入配对码后，插件会自动安装。完成后请重启 Rockpile。",
        "onboard.pairingCode": "配对码",
        "onboard.installing": "正在安装插件…",
        "onboard.installError": "安装出了点问题",
        "onboard.checkPermission": "检查 ~/.rockpile 目录权限",
        "onboard.testingConn": "正在测试连接…",
        "onboard.allReady": "一切就绪！",
        "onboard.hostReady": "服务端已就位，重启 Rockpile 就能生效",
        "onboard.goFind": "去 Notch 栏找你的伙伴吧 🐚🦞",
        "onboard.pluginPath": "插件位置",
        "onboard.eventTarget": "事件发往",
        "onboard.connTestFailed": "插件已安装，但连接测试失败",
        "onboard.skipHint": "可以先跳过，之后在设置中重试",
        "onboard.back": "上一步",
        "onboard.next": "下一步",
        "onboard.reconfigure": "重配置",
        "onboard.keepSettings": "保持设置 →",
        "onboard.processing": "处理中…",
        "onboard.start": "开始使用",
        "onboard.openSettings": "打开完整设置",
        "onboard.retry": "重试",
        "onboard.listeningTCP": "已在 TCP:{port} 端口等待事件",
        "onboard.monitorCodeHint": "输入野生龙虾端（跑 Rockpile 的 Mac）上显示的配对码",

        // ── Onboarding (additional) ──
        "onboard.o2Hint": "🫧 氧气追踪配置",
        "onboard.meterMode": "计量模式",
        "onboard.usageAPI": "用量 API 监控",
        "onboard.testConn": "测试连接",
        "onboard.verifying": "验证中…",
        "onboard.valid": "✓ 有效",
        "onboard.copied": "已复制",
        "onboard.copyCode": "复制配对码",
        "onboard.badCode": "配对码格式不正确",
        "onboard.cantConnect": "无法连接到",
        "onboard.retryInstall": "重试安装",
        "onboard.done": "完成",
        "onboard.skip": "跳过",

        // ── Usage API ──
        "usage.noAdminKey": "未配置管理员 API Key",
        "usage.noProvider": "未配置提供商",
        "usage.noTeamId": "未设置 Team ID",
        "usage.notHTTP": "非 HTTP 响应",
        "usage.parseFailed": "JSON 解析失败",
        "usage.noData": "无 data 数组",
    ]

    private static let zhArrays: [String: [String]] = [
        // ── Crawfish Tap ──
        "rx.crawfish.tap.idle": ["嗯?", "干嘛~", "!"],
        "rx.crawfish.tap.working": ["忙着呢!", "别戳了", "嘶…"],
        "rx.crawfish.tap.thinking": ["嘘…", "在想…", "别打扰"],
        "rx.crawfish.tap.sleeping": ["哈欠~", "醒了!", "嗯…?"],
        "rx.crawfish.tap.waiting": ["无聊~", "快点啊", "哎…"],
        "rx.crawfish.tap.error": ["呜呜", "救命", "坏了!"],
        "rx.crawfish.tap.compacting": ["好挤!", "嘶…", "等等…"],
        // ── Crab Tap ──
        "rx.crab.tap.idle": ["…?", "~", "嗯"],
        "rx.crab.tap.working": ["别碰", "忙", "…!"],
        "rx.crab.tap.thinking": ["嘘", "嗯…", "…"],
        "rx.crab.tap.sleeping": ["…醒了", "唔~", "哈欠"],
        "rx.crab.tap.waiting": ["…", "嗯…", "等…"],
        "rx.crab.tap.error": ["!!", "呜", "痛…"],
        "rx.crab.tap.compacting": ["挤…", "嘶", "…!"],
        // ── Crawfish Love ──
        "rx.crawfish.love.idle": ["嘿嘿~", "开心!", "喜欢~"],
        "rx.crawfish.love.working": ["谢谢~", "嗯嗯~", "^^"],
        "rx.crawfish.love.sleeping": ["嗯…❤", "好暖~", "继续摸"],
        "rx.crawfish.love.error": ["谢谢…", "好多了", "❤"],
        "rx.crawfish.love.compacting": ["别闹~", "等下…", "嗯~"],
        // ── Crab Love ──
        "rx.crab.love.idle": ["…❤", "嗯~", "//"],
        "rx.crab.love.working": ["嗯…", "~", "❤"],
        "rx.crab.love.sleeping": ["嗯…❤", "暖~", "…"],
        "rx.crab.love.error": ["…谢", "好些了", "❤"],
        "rx.crab.love.compacting": ["…~", "嗯", "等等"],
        // ── Feed ──
        "rx.crawfish.feed": ["好吃!", "再来!", "美味~"],
        "rx.crawfish.feed.overfed": ["吃不下了!", "撑死了~", "饱了饱了"],
        "rx.crab.feed": ["嗯~好吃", "…不错", "谢谢~"],
        "rx.crab.feed.overfed": ["…饱了", "不要了", "吃不动"],
        // ── Punishment ──
        "rx.crawfish.punish": ["好痛!", "别打了!", "呜呜呜"],
        "rx.crab.punish": ["…!", "别碰!", "缩"],
        // ── Interaction ──
        "rx.crawfish.interact.bump": ["嘿!", "碰!", "小心~"],
        "rx.crawfish.interact.play": ["来玩!", "追你~", "跑啊!"],
        "rx.crawfish.interact.highFive": ["碰拳!", "耶!", "来!"],
        "rx.crawfish.interact.nuzzle": ["嘿嘿~", "暖~", "靠靠~"],
        "rx.crab.interact.bump": ["…!", "哎", "轻点"],
        "rx.crab.interact.play": ["…好吧", "嗯~", "慢点"],
        "rx.crab.interact.highFive": ["…碰", "嗯!", "~"],
        "rx.crab.interact.nuzzle": ["…❤", "嗯~", "暖"],
        // ── Bubble ──
        "bubble.idle": ["🦞 待命中~", "摸鱼ing…", "有活干吗？", "好无聊啊", "水里真舒服", "🫧", "晒太阳~", "钳子磨好了"],
        "bubble.thinking": ["嗯…", "让我想想", "💭", "这个有点难", "思考中…", "🤔 hmm"],
        "bubble.working": ["码代码中…", "⚡ 干活!", "别打扰我", "认真.jpg", "搬砖ing", "🔧 修修改改", "快好了…"],
        "bubble.waiting": ["等等等…", "还没好吗", "⏳", "打个哈欠~", "无聊…"],
        "bubble.error": ["❗ 出bug了", "呜呜呜", "救命…", "💥 炸了", "怎么回事", "这不对啊"],
        "bubble.sleeping": ["💤 zzz", "别吵…", "做梦中", "zZzZz", "呼噜~"],
        "bubble.compacting": ["压缩中…", "🗜️", "整理记忆", "瘦身!"],
        "bubble.dead": ["💀", "GG", "再见世界…", "没氧气了", "翻肚了…"],
        "bubble.warningO2": ["有点缺氧…", "氧气不多了", "喘不上气", "🫧快没了"],
        "bubble.lowO2": ["快窒息了!", "呼吸困难…", "快喂我!", "氧气…氧气!"],
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - English (en)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static let enStrings: [String: String] = [
        // ── Creature ──
        "creature.hermitCrab": "Hermit Crab",
        "creature.crawfish": "Crawfish",
        "creature.local": "Local",
        "creature.remote": "Remote",

        // ── State ──
        "state.idle": "Idle",
        "state.thinking": "Thinking…",
        "state.working": "Working…",
        "state.sleeping": "Sleeping",
        "state.compacting": "Compacting…",
        "state.waiting": "Waiting…",
        "state.error": "Error",

        // ── O₂ ──
        "o2.normal": "Normal",
        "o2.warning": "Warning",
        "o2.danger": "Danger",
        "o2.critical": "Critical",
        "o2.ko": "K.O.",
        "o2.lowOxygen": "Low O₂",
        "o2.used": "Used",

        // ── Header ──
        "header.pin": "Pin Panel",
        "header.unpin": "Unpin",
        "header.settings": "Settings",
        "header.close": "Close Panel",

        // ── Dashboard ──
        "dash.footprints": "Footprints",
        "dash.activity": "Activity",
        "dash.waiting": "Waiting for connection",
        "dash.waitingDesc": "Start Claude Code or Openclaw\nCreatures will appear in the pond",
        "dash.model": "Model",
        "dash.input": "Input",
        "dash.output": "Output",
        "dash.cacheRead": "Cache R",
        "dash.cacheWrite": "Cache W",
        "dash.noDetail": "No details",
        "dash.tapCollapse": "Tap to collapse",
        "dash.tapDetail": "Tap for details",
        "dash.burnRate": "Burn Rate",
        "dash.eta": "ETA",
        "dash.dailyProgress": "Daily",
        "dash.pace.ahead": "Ahead",
        "dash.pace.onTrack": "On Track",
        "dash.pace.behind": "Behind",
        "dash.pace.idle": "Idle",

        // ── Settings ──
        "settings.title": "Settings",
        "settings.connection": "Connection",
        "settings.mode": "Mode",
        "settings.method": "Method",
        "settings.port": "Port",
        "settings.remoteHost": "Remote Host",
        "settings.localIP": "Local IP",
        "settings.localO2": "Local O₂ (Hermit Crab)",
        "settings.remoteO2": "Remote O₂ (Crawfish)",
        "settings.dailyQuota": "Daily Quota",
        "settings.auto": "tokens (auto)",
        "settings.claudeQuota": "Claude Quota",
        "settings.paidUsage": "Pay-as-you-go",
        "settings.bottleCapacity": "Tank Capacity",
        "settings.detected": "Detected",
        "settings.actions": "Actions",
        "settings.reinstallPlugin": "Reinstall Plugin",
        "settings.resetSettings": "Reset Settings",
        "settings.reinstallDone": "✓ Plugin reinstalled",
        "settings.reinstallNA": "Monitor mode — no plugin needed",
        "settings.language": "Language",
        "settings.startup": "Startup",
        "settings.launchAtLogin": "Launch at Login",
        "settings.quit": "Quit Rockpile",

        // ── Menu ──
        "menu.activeSessions": "active sessions",
        "menu.depleted": "Depleted",
        "menu.noSession": "No active session",
        "menu.pairCode": "Pair Code",
        "menu.launchAtLogin": "Launch at Login",
        "menu.settings": "Settings…",
        "menu.exportLog": "Export Logs…",
        "menu.openLogFolder": "Open Log Folder",
        "menu.quit": "Quit Rockpile",

        // ── Role ──
        "role.local": "Local Mode",
        "role.monitor": "Remote Monitor",
        "role.host": "Rockpile Server",
        "role.unknown": "Not configured",

        // ── Input ──
        "input.placeholder": "Send command... (↵)",
        "input.send": "Send command",
        "input.sent": "Sent",
        "input.waitingConnection": "Waiting for connection...",
        "input.noSession": "No active session",

        // ── Time ──
        "time.second": "s",
        "time.minute": "m",
        "time.hour": "h",
        "time.lessThan1s": "<1s",
        "time.yesterday": "Yesterday",
        "time.noTools": "No tools",

        // ── Sprite Info ──
        "sprite.accessCrab": "Hermit Crab",
        "sprite.accessCrawfish": "Crawfish",
        "sprite.accessHint": "Tap to interact, long-press for info, right-click to feed",
        "sprite.noSession": "No active session",

        // ── Feed ──
        "feed.overfed": "Too full…",
        "feed.feed": "Feed",
        "feed.cooldown": "Cooldown",

        // ── Command ──
        "cmd.queued": "Command already queued",
        "cmd.unknown": "Unknown error",
        "cmd.failed": "Send failed",
        "cmd.expired": "Command expired",
        "cmd.emergencyWIP": "Emergency stop — WIP",

        // ── Version Notes ──
        "version.note1": "🐚 Hermit Crab: Local Claude Code companion",
        "version.note2": "🦞 Dual ecosystem: Hermit Crab (local) + Crawfish (remote)",
        "version.note3": "Dual O₂ bars: Independent local/remote token tracking",
        "version.note4": "Dashboard dual-source cards: Separate local and remote status",
        "version.note5": "Pond layers: Hermit crab crawls on bottom, crawfish swims above",

        // ── Provider ──
        "provider.claudeSub": "Claude Sub",
        "provider.claudeAPI": "Anthropic API",
        "provider.openAI": "OpenAI",
        "provider.gemini": "Gemini",
        "provider.xAI": "xAI",
        "provider.deepSeek": "DeepSeek",
        "provider.unknown": "Unknown",
        "provider.dailyQuota": "Daily Quota",
        "provider.payAsYouGo": "Pay-as-you-go",

        // ── Onboarding ──
        "onboard.selectLanguage": "Select Language",
        "onboard.thisUpdate": "This Update",
        "onboard.currentSettings": "Current Settings",
        "onboard.roleQuestion": "What role does this Mac play?",
        "onboard.roleLocal": "Local Use",
        "onboard.roleLocalDesc": "Hermit Crab (local Claude) + optional remote Crawfish (Openclaw)",
        "onboard.roleMonitor": "Fish Tank (Monitor)",
        "onboard.roleMonitorDesc": "This Mac only has the tank — enter a pairing code to bring the crawfish over",
        "onboard.roleHost": "Server (Headless)",
        "onboard.roleHostDesc": "Runs backend only — after pairing, crawfish swims to the remote tank",
        "onboard.localMode": "Local Mode",
        "onboard.localCrab": "🐚 Hermit Crab monitors local Claude Code",
        "onboard.localCrawfish": "🦞 Crawfish monitors remote Openclaw (optional)",
        "onboard.foundClaude": "Found Claude",
        "onboard.autoInstall": "Auto-install plugin",
        "onboard.localComm": "Local Communication",
        "onboard.unixSocket": "Unix Socket",
        "onboard.remoteConn": "Remote Connection",
        "onboard.gatewayWS": "Gateway WebSocket",
        "onboard.monitorMode": "Fish Tank (Monitor)",
        "onboard.enterCode": "Enter Pairing Code",
        "onboard.codeHint": "Alphanumeric only, case-insensitive",
        "onboard.hostSide": "Server side",
        "onboard.hostMode": "Wild Crawfish (Server)",
        "onboard.hostCodeHint": "Share this pairing code with the monitor Mac",
        "onboard.foundRockpile": "Found Rockpile",
        "onboard.notFoundRockpile": "Rockpile not found",
        "onboard.needInstall": "Install Rockpile first to continue",
        "onboard.waitingTank": "Waiting for tank",
        "onboard.waitingTankDesc": "Enter the pairing code on the monitor Mac. Plugin installs automatically. Restart Rockpile when done.",
        "onboard.pairingCode": "Pairing Code",
        "onboard.installing": "Installing plugin…",
        "onboard.installError": "Installation failed",
        "onboard.checkPermission": "Check ~/.rockpile directory permissions",
        "onboard.testingConn": "Testing connection…",
        "onboard.allReady": "All set!",
        "onboard.hostReady": "Server is ready — restart Rockpile to apply",
        "onboard.goFind": "Find your companions in the Notch bar! 🐚🦞",
        "onboard.pluginPath": "Plugin path",
        "onboard.eventTarget": "Events sent to",
        "onboard.connTestFailed": "Plugin installed, but connection test failed",
        "onboard.skipHint": "Skip for now — retry in settings later",
        "onboard.back": "Back",
        "onboard.next": "Next",
        "onboard.reconfigure": "Reconfigure",
        "onboard.keepSettings": "Keep Settings →",
        "onboard.processing": "Processing…",
        "onboard.start": "Get Started",
        "onboard.openSettings": "Open Full Settings",
        "onboard.retry": "Retry",
        "onboard.listeningTCP": "Listening on TCP:{port} for events",
        "onboard.monitorCodeHint": "Enter the pairing code shown on the server Mac running Rockpile",

        // ── Onboarding (additional) ──
        "onboard.o2Hint": "🫧 Oxygen tracking config",
        "onboard.meterMode": "Meter Mode",
        "onboard.usageAPI": "Usage API Monitoring",
        "onboard.testConn": "Test Connection",
        "onboard.verifying": "Verifying…",
        "onboard.valid": "✓ Valid",
        "onboard.copied": "Copied",
        "onboard.copyCode": "Copy Pairing Code",
        "onboard.badCode": "Invalid pairing code format",
        "onboard.cantConnect": "Cannot connect to",
        "onboard.retryInstall": "Retry Install",
        "onboard.done": "Done",
        "onboard.skip": "Skip",

        // ── Usage API ──
        "usage.noAdminKey": "Admin API key not configured",
        "usage.noProvider": "Provider not configured",
        "usage.noTeamId": "Team ID not set",
        "usage.notHTTP": "Non-HTTP response",
        "usage.parseFailed": "JSON parse failed",
        "usage.noData": "No data array",
    ]

    private static let enArrays: [String: [String]] = [
        // ── Crawfish Tap ──
        "rx.crawfish.tap.idle": ["Hm?", "Hey~", "!"],
        "rx.crawfish.tap.working": ["Busy!", "Stop it", "Hiss…"],
        "rx.crawfish.tap.thinking": ["Shh…", "Thinking…", "Don't"],
        "rx.crawfish.tap.sleeping": ["Yawn~", "Awake!", "Hm…?"],
        "rx.crawfish.tap.waiting": ["Bored~", "Hurry up", "Sigh…"],
        "rx.crawfish.tap.error": ["Ow…", "Help!", "Broken!"],
        "rx.crawfish.tap.compacting": ["Tight!", "Hiss…", "Wait…"],
        // ── Crab Tap ──
        "rx.crab.tap.idle": ["…?", "~", "Hm"],
        "rx.crab.tap.working": ["Don't", "Busy", "…!"],
        "rx.crab.tap.thinking": ["Shh", "Hm…", "…"],
        "rx.crab.tap.sleeping": ["…awake", "Mm~", "Yawn"],
        "rx.crab.tap.waiting": ["…", "Hm…", "Wait…"],
        "rx.crab.tap.error": ["!!", "Ow", "Ouch…"],
        "rx.crab.tap.compacting": ["Tight…", "Hiss", "…!"],
        // ── Crawfish Love ──
        "rx.crawfish.love.idle": ["Hehe~", "Happy!", "Like~"],
        "rx.crawfish.love.working": ["Thanks~", "Mm~", "^^"],
        "rx.crawfish.love.sleeping": ["Mm…❤", "Warm~", "More~"],
        "rx.crawfish.love.error": ["Thanks…", "Better~", "❤"],
        "rx.crawfish.love.compacting": ["Not now~", "Wait…", "Mm~"],
        // ── Crab Love ──
        "rx.crab.love.idle": ["…❤", "Mm~", "//"],
        "rx.crab.love.working": ["Mm…", "~", "❤"],
        "rx.crab.love.sleeping": ["Mm…❤", "Warm~", "…"],
        "rx.crab.love.error": ["…thx", "Better", "❤"],
        "rx.crab.love.compacting": ["…~", "Mm", "Wait"],
        // ── Feed ──
        "rx.crawfish.feed": ["Yum!", "More!", "Tasty~"],
        "rx.crawfish.feed.overfed": ["Too full!", "So stuffed~", "Enough!"],
        "rx.crab.feed": ["Mm~yum", "…nice", "Thanks~"],
        "rx.crab.feed.overfed": ["…full", "No more", "Can't eat"],
        // ── Punishment ──
        "rx.crawfish.punish": ["Ouch!", "Stop it!", "Waah!"],
        "rx.crab.punish": ["…!", "Don't!", "Hide"],
        // ── Interaction ──
        "rx.crawfish.interact.bump": ["Hey!", "Bump!", "Watch~"],
        "rx.crawfish.interact.play": ["Play!", "Chase~", "Run!"],
        "rx.crawfish.interact.highFive": ["High five!", "Yay!", "Go!"],
        "rx.crawfish.interact.nuzzle": ["Hehe~", "Warm~", "Cozy~"],
        "rx.crab.interact.bump": ["…!", "Oh", "Gentle"],
        "rx.crab.interact.play": ["…okay", "Mm~", "Slow"],
        "rx.crab.interact.highFive": ["…bump", "Mm!", "~"],
        "rx.crab.interact.nuzzle": ["…❤", "Mm~", "Warm"],
        // ── Bubble ──
        "bubble.idle": ["🦞 Standing by~", "Chilling…", "Any work?", "So bored~", "Water's nice", "🫧", "Sunbathing~", "Claws ready!"],
        "bubble.thinking": ["Hmm…", "Let me think", "💭", "Tricky one", "Thinking…", "🤔 hmm"],
        "bubble.working": ["Coding…", "⚡ Working!", "Don't bother", "Focus mode", "Building…", "🔧 Fixing", "Almost done…"],
        "bubble.waiting": ["Waiting…", "Not yet?", "⏳", "Yawn~", "Bored…"],
        "bubble.error": ["❗ Bug!", "Ow…", "Help…", "💥 Boom", "What happened", "Not right"],
        "bubble.sleeping": ["💤 zzz", "Shh…", "Dreaming", "zZzZz", "Snore~"],
        "bubble.compacting": ["Compacting…", "🗜️", "Tidying up", "Slimming!"],
        "bubble.dead": ["💀", "GG", "Goodbye…", "No oxygen", "Belly up…"],
        "bubble.warningO2": ["Running low…", "Need air…", "Gasp~", "🫧 Low O₂"],
        "bubble.lowO2": ["Can't breathe!", "Help! Air!", "Feed me!", "Oxygen!"],
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Japanese (ja)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static let jaStrings: [String: String] = [
        // ── Creature ──
        "creature.hermitCrab": "ヤドカリ",
        "creature.crawfish": "ザリガニ",
        "creature.local": "ローカル",
        "creature.remote": "リモート",

        // ── State ──
        "state.idle": "待機",
        "state.thinking": "考え中…",
        "state.working": "作業中…",
        "state.sleeping": "休眠",
        "state.compacting": "圧縮中…",
        "state.waiting": "待機中…",
        "state.error": "エラー",

        // ── O₂ ──
        "o2.normal": "正常",
        "o2.warning": "警告",
        "o2.danger": "危険",
        "o2.critical": "臨界",
        "o2.ko": "K.O.",
        "o2.lowOxygen": "低酸素",
        "o2.used": "使用量",

        // ── Header ──
        "header.pin": "パネル固定",
        "header.unpin": "固定解除",
        "header.settings": "設定",
        "header.close": "パネルを閉じる",

        // ── Dashboard ──
        "dash.footprints": "足跡",
        "dash.activity": "アクティビティ",
        "dash.waiting": "接続待ち",
        "dash.waitingDesc": "Claude Code または Openclaw を起動してください\n生き物が池に現れます",
        "dash.model": "モデル",
        "dash.input": "入力",
        "dash.output": "出力",
        "dash.cacheRead": "キャッシュ読",
        "dash.cacheWrite": "キャッシュ書",
        "dash.noDetail": "詳細データなし",
        "dash.tapCollapse": "タップで折りたたむ",
        "dash.tapDetail": "タップで詳細表示",
        "dash.burnRate": "消費率",
        "dash.eta": "推定枯渇",
        "dash.dailyProgress": "日次進捗",
        "dash.pace.ahead": "速い",
        "dash.pace.onTrack": "正常",
        "dash.pace.behind": "遅い",
        "dash.pace.idle": "待機",

        // ── Settings ──
        "settings.title": "設定",
        "settings.connection": "接続",
        "settings.mode": "モード",
        "settings.method": "方式",
        "settings.port": "ポート",
        "settings.remoteHost": "リモートホスト",
        "settings.localIP": "ローカルIP",
        "settings.localO2": "ローカル O₂ (ヤドカリ)",
        "settings.remoteO2": "リモート O₂ (ザリガニ)",
        "settings.dailyQuota": "日次クォータ",
        "settings.auto": "トークン (自動)",
        "settings.claudeQuota": "Claude クォータ",
        "settings.paidUsage": "従量課金",
        "settings.bottleCapacity": "タンク容量",
        "settings.detected": "検出済み",
        "settings.actions": "操作",
        "settings.reinstallPlugin": "プラグイン再インストール",
        "settings.resetSettings": "設定リセット",
        "settings.reinstallDone": "✓ プラグインを再インストールしました",
        "settings.reinstallNA": "モニターモードではプラグイン不要です",
        "settings.language": "言語",
        "settings.startup": "起動",
        "settings.launchAtLogin": "ログイン時に起動",
        "settings.quit": "Rockpile を終了",

        // ── Menu ──
        "menu.activeSessions": "個のセッション",
        "menu.depleted": "枯渇",
        "menu.noSession": "アクティブなセッションなし",
        "menu.pairCode": "ペアコード",
        "menu.launchAtLogin": "ログイン時に起動",
        "menu.settings": "設定…",
        "menu.exportLog": "ログをエクスポート…",
        "menu.openLogFolder": "ログフォルダを開く",
        "menu.quit": "Rockpile を終了",

        // ── Role ──
        "role.local": "ローカルモード",
        "role.monitor": "リモートモニター",
        "role.host": "Rockpile サーバー",
        "role.unknown": "未設定",

        // ── Input ──
        "input.placeholder": "コマンドを送信... (↵)",
        "input.send": "コマンド送信",
        "input.sent": "送信済み",
        "input.waitingConnection": "接続待ち...",
        "input.noSession": "アクティブなセッションなし",

        // ── Time ──
        "time.second": "秒",
        "time.minute": "分",
        "time.hour": "時",
        "time.lessThan1s": "<1秒",
        "time.yesterday": "昨日",
        "time.noTools": "ツールなし",

        // ── Sprite Info ──
        "sprite.accessCrab": "ヤドカリ",
        "sprite.accessCrawfish": "ザリガニ",
        "sprite.accessHint": "タップで交流、長押しで情報、右クリックで餌やり",
        "sprite.noSession": "アクティブなセッションなし",

        // ── Feed ──
        "feed.overfed": "お腹いっぱい…",
        "feed.feed": "餌やり",
        "feed.cooldown": "クールダウン",

        // ── Command ──
        "cmd.queued": "コマンドがキューに入っています",
        "cmd.unknown": "不明なエラー",
        "cmd.failed": "送信失敗",
        "cmd.expired": "コマンド期限切れ",
        "cmd.emergencyWIP": "緊急停止 — 開発中",

        // ── Version Notes ──
        "version.note1": "🐚 ヤドカリ: ローカル Claude Code 専用コンパニオン",
        "version.note2": "🦞 デュアルエコシステム: ヤドカリ(ローカル) + ザリガニ(リモート)",
        "version.note3": "デュアル O₂ バー: ローカル/リモートのトークン使用量を個別追跡",
        "version.note4": "ダッシュボード: ローカルとリモートのステータスを個別表示",
        "version.note5": "池の階層: ヤドカリは底を這い、ザリガニは上層を泳ぐ",

        // ── Provider ──
        "provider.claudeSub": "Claude サブ",
        "provider.claudeAPI": "Anthropic API",
        "provider.openAI": "OpenAI",
        "provider.gemini": "Gemini",
        "provider.xAI": "xAI",
        "provider.deepSeek": "DeepSeek",
        "provider.unknown": "不明",
        "provider.dailyQuota": "日次クォータ",
        "provider.payAsYouGo": "従量制",

        // ── Onboarding ──
        "onboard.selectLanguage": "言語を選択",
        "onboard.thisUpdate": "今回のアップデート",
        "onboard.currentSettings": "現在の設定",
        "onboard.roleQuestion": "この Mac の役割は？",
        "onboard.roleLocal": "ローカル使用",
        "onboard.roleLocalDesc": "ヤドカリ(ローカル Claude) + オプションのザリガニ(Openclaw)",
        "onboard.roleMonitor": "水槽（モニター）",
        "onboard.roleMonitorDesc": "水槽のみ — ペアリングコードを入力してザリガニを呼び寄せる",
        "onboard.roleHost": "サーバー（ヘッドレス）",
        "onboard.roleHostDesc": "バックエンドのみ — ペアリング後にザリガニがリモート水槽へ",
        "onboard.localMode": "ローカルモード",
        "onboard.localCrab": "🐚 ヤドカリがローカル Claude Code を監視",
        "onboard.localCrawfish": "🦞 ザリガニがリモート Openclaw を監視（オプション）",
        "onboard.foundClaude": "Claude を検出",
        "onboard.autoInstall": "プラグイン自動インストール",
        "onboard.localComm": "ローカル通信",
        "onboard.unixSocket": "Unix Socket",
        "onboard.remoteConn": "リモート接続",
        "onboard.gatewayWS": "Gateway WebSocket",
        "onboard.monitorMode": "水槽（モニター）",
        "onboard.enterCode": "ペアリングコードを入力",
        "onboard.codeHint": "英数字のみ、大文字小文字区別なし",
        "onboard.hostSide": "サーバー側",
        "onboard.hostMode": "野生ザリガニ（サーバー）",
        "onboard.hostCodeHint": "このペアリングコードをモニター Mac に共有してください",
        "onboard.foundRockpile": "Rockpile を検出",
        "onboard.notFoundRockpile": "Rockpile が見つかりません",
        "onboard.needInstall": "続行するには Rockpile のインストールが必要です",
        "onboard.waitingTank": "水槽の接続待ち",
        "onboard.waitingTankDesc": "モニター Mac でペアリングコードを入力するとプラグインが自動インストールされます。完了後 Rockpile を再起動してください。",
        "onboard.pairingCode": "ペアリングコード",
        "onboard.installing": "プラグインをインストール中…",
        "onboard.installError": "インストール失敗",
        "onboard.checkPermission": "~/.rockpile ディレクトリの権限を確認してください",
        "onboard.testingConn": "接続テスト中…",
        "onboard.allReady": "準備完了！",
        "onboard.hostReady": "サーバー準備完了 — Rockpile を再起動して反映",
        "onboard.goFind": "Notch バーであなたの仲間を見つけよう！🐚🦞",
        "onboard.pluginPath": "プラグインパス",
        "onboard.eventTarget": "イベント送信先",
        "onboard.connTestFailed": "プラグインはインストール済みですが、接続テストに失敗しました",
        "onboard.skipHint": "スキップして後で設定から再試行できます",
        "onboard.back": "戻る",
        "onboard.next": "次へ",
        "onboard.reconfigure": "再設定",
        "onboard.keepSettings": "設定を保持 →",
        "onboard.processing": "処理中…",
        "onboard.start": "はじめる",
        "onboard.openSettings": "詳細設定を開く",
        "onboard.retry": "再試行",
        "onboard.listeningTCP": "TCP:{port} でイベントを待受中",
        "onboard.monitorCodeHint": "Rockpile を実行中のサーバー Mac に表示されたペアリングコードを入力",

        // ── Onboarding (additional) ──
        "onboard.o2Hint": "🫧 酸素トラッキング設定",
        "onboard.meterMode": "計量モード",
        "onboard.usageAPI": "使用量 API モニタリング",
        "onboard.testConn": "接続テスト",
        "onboard.verifying": "検証中…",
        "onboard.valid": "✓ 有効",
        "onboard.copied": "コピー済み",
        "onboard.copyCode": "ペアリングコードをコピー",
        "onboard.badCode": "ペアリングコードの形式が不正です",
        "onboard.cantConnect": "接続できません：",
        "onboard.retryInstall": "再インストール",
        "onboard.done": "完了",
        "onboard.skip": "スキップ",

        // ── Usage API ──
        "usage.noAdminKey": "管理者 API キーが未設定",
        "usage.noProvider": "プロバイダーが未設定",
        "usage.noTeamId": "チーム ID が未設定",
        "usage.notHTTP": "非 HTTP レスポンス",
        "usage.parseFailed": "JSON パース失敗",
        "usage.noData": "データ配列なし",
    ]

    private static let jaArrays: [String: [String]] = [
        // ── Crawfish Tap ──
        "rx.crawfish.tap.idle": ["ん？", "なに〜", "！"],
        "rx.crawfish.tap.working": ["忙しい！", "やめて", "シー…"],
        "rx.crawfish.tap.thinking": ["しー…", "考え中…", "邪魔"],
        "rx.crawfish.tap.sleeping": ["ふわぁ〜", "起きた！", "んー？"],
        "rx.crawfish.tap.waiting": ["暇〜", "早くして", "はぁ…"],
        "rx.crawfish.tap.error": ["痛い…", "助けて", "壊れた！"],
        "rx.crawfish.tap.compacting": ["きつい！", "シー…", "待って…"],
        // ── Crab Tap ──
        "rx.crab.tap.idle": ["…？", "〜", "ん"],
        "rx.crab.tap.working": ["触らないで", "忙しい", "…！"],
        "rx.crab.tap.thinking": ["しー", "んー…", "…"],
        "rx.crab.tap.sleeping": ["…起きた", "ん〜", "ふわぁ"],
        "rx.crab.tap.waiting": ["…", "んー…", "待ち…"],
        "rx.crab.tap.error": ["！！", "痛い", "いたっ…"],
        "rx.crab.tap.compacting": ["きつい…", "シー", "…！"],
        // ── Crawfish Love ──
        "rx.crawfish.love.idle": ["えへへ〜", "嬉しい！", "好き〜"],
        "rx.crawfish.love.working": ["ありがと〜", "んん〜", "^^"],
        "rx.crawfish.love.sleeping": ["ん…❤", "あったかい〜", "もっと〜"],
        "rx.crawfish.love.error": ["ありがと…", "楽になった", "❤"],
        "rx.crawfish.love.compacting": ["今はやめて〜", "ちょっと…", "ん〜"],
        // ── Crab Love ──
        "rx.crab.love.idle": ["…❤", "ん〜", "//"],
        "rx.crab.love.working": ["ん…", "〜", "❤"],
        "rx.crab.love.sleeping": ["ん…❤", "暖かい〜", "…"],
        "rx.crab.love.error": ["…ありがと", "楽になった", "❤"],
        "rx.crab.love.compacting": ["…〜", "ん", "待って"],
        // ── Feed ──
        "rx.crawfish.feed": ["おいしい！", "もっと！", "うまい〜"],
        "rx.crawfish.feed.overfed": ["もう食べれない！", "お腹パンパン〜", "もう十分！"],
        "rx.crab.feed": ["ん〜おいしい", "…いいね", "ありがと〜"],
        "rx.crab.feed.overfed": ["…お腹いっぱい", "もういい", "食べれない"],
        // ── Punishment ──
        "rx.crawfish.punish": ["痛い！", "やめて！", "うわーん"],
        "rx.crab.punish": ["…！", "触らないで！", "隠れる"],
        // ── Interaction ──
        "rx.crawfish.interact.bump": ["おっ！", "どん！", "気をつけて〜"],
        "rx.crawfish.interact.play": ["遊ぼう！", "追いかけっこ〜", "走れ！"],
        "rx.crawfish.interact.highFive": ["ハイタッチ！", "やった！", "いくぞ！"],
        "rx.crawfish.interact.nuzzle": ["えへへ〜", "暖かい〜", "くっつき〜"],
        "rx.crab.interact.bump": ["…！", "おっと", "やさしくして"],
        "rx.crab.interact.play": ["…いいよ", "ん〜", "ゆっくり"],
        "rx.crab.interact.highFive": ["…ぺち", "ん！", "〜"],
        "rx.crab.interact.nuzzle": ["…❤", "ん〜", "暖かい"],
        // ── Bubble ──
        "bubble.idle": ["🦞 待機中〜", "サボり中…", "仕事ある？", "暇だなぁ", "水が気持ちいい", "🫧", "日向ぼっこ〜", "ハサミ準備OK"],
        "bubble.thinking": ["うーん…", "考え中", "💭", "ちょっと難しい", "思考中…", "🤔 hmm"],
        "bubble.working": ["コーディング中…", "⚡ 作業中!", "邪魔しないで", "集中.jpg", "ビルド中", "🔧 修正中", "もうすぐ…"],
        "bubble.waiting": ["待ってる…", "まだ？", "⏳", "あくび〜", "暇…"],
        "bubble.error": ["❗ バグだ！", "痛い…", "助けて…", "💥 爆発", "どうした", "おかしい"],
        "bubble.sleeping": ["💤 zzz", "しー…", "夢の中", "zZzZz", "グー〜"],
        "bubble.compacting": ["圧縮中…", "🗜️", "整理中", "ダイエット!"],
        "bubble.dead": ["💀", "GG", "さよなら…", "酸素がない", "ひっくり返った…"],
        "bubble.warningO2": ["酸素少ない…", "息が…", "はぁはぁ", "🫧酸素低下"],
        "bubble.lowO2": ["息できない！", "助けて！空気！", "餌を！", "酸素！"],
    ]
}
