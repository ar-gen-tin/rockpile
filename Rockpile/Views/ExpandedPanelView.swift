import SwiftUI
import ServiceManagement

/// 展开面板视图 — NotchContentView 下方 50% 区域
///
/// v2.0 双源堆叠布局：
/// 1. **本地卡片**: 寄居蟹 · Claude Code · O₂ 条 · 活动
/// 2. **远程卡片**: 小龙虾 · Openclaw · O₂ 条 · 活动
/// 3. **足迹**: 混合时间线 (🐚/🦞)
/// 4. **输入框**: 发送指令
///
/// 设置视图保留（从 v1.x 扩展双 O₂ 配置）。
struct ExpandedPanelView: View {
    let sessionStore: SessionStore
    @Binding var showingSettings: Bool
    @Binding var isActivityCollapsed: Bool
    @State private var localCardExpanded = false
    @State private var remoteCardExpanded = false
    @State private var expandedRecordId: UUID?

    // Settings state
    @State private var localTankCapacity: Int = AppSettings.localOxygenTankCapacity
    @State private var remoteTankCapacity: Int = AppSettings.remoteOxygenTankCapacity
    @State private var localOxygenMode: String = AppSettings.localOxygenMode
    @State private var remoteOxygenMode: String = AppSettings.remoteOxygenMode
    @State private var reinstallMessage: String?

    var body: some View {
        if showingSettings {
            settingsView
        } else {
            dashboardView
        }
    }

    // MARK: - Dashboard View (Dual Source)

    @ViewBuilder
    private var dashboardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 错误 toast (CodexBar 风格) ──
            if let error = StateMachine.shared.lastError {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DS.Semantic.warning)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundColor(DS.TextColor.primary)
                        .lineLimit(1)
                    Spacer()
                    gatewayStatusView
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .background(DS.Semantic.warning.opacity(DS.Opacity.ghost))
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // ── Gateway 连接状态 (无错误时独立显示) ──
                HStack {
                    Spacer()
                    gatewayStatusView
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.xxs)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.sm) {
                    // ── 双源合并行: 提供商 + 状态 ──
                    DualSourceInfoRow(
                        localSession: sessionStore.effectiveLocalSession,
                        remoteSession: sessionStore.effectiveRemoteSession,
                        localSessionCount: sessionStore.localSessions.count,
                        remoteSessionCount: sessionStore.remoteSessions.count,
                        localExpanded: $localCardExpanded,
                        remoteExpanded: $remoteCardExpanded
                    )

                    // ── O₂ 双条合并 (对齐 InfoRow 布局) ──
                    HStack(spacing: 0) {
                        CompactOxygenBarView(
                            tracker: sessionStore.localTokenTracker,
                            creatureType: .hermitCrab
                        )
                        .padding(.horizontal, DS.Space.sm)
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(DS.Surface.divider)
                            .frame(width: 1)
                            .padding(.vertical, 2)

                        CompactOxygenBarView(
                            tracker: sessionStore.remoteTokenTracker,
                            creatureType: .crawfish
                        )
                        .padding(.horizontal, DS.Space.sm)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, DS.Space.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Compact.cardRadius)
                            .fill(DS.Surface.raised)
                    )

                    // ── Token 消耗概览（空闲时也显示日进度/待命状态）──
                    if sessionStore.localTokenTracker.hasUsageData || sessionStore.remoteTokenTracker.hasUsageData || sessionStore.activeSessionCount > 0 {
                        TokenConsumptionCard(
                            localTracker: sessionStore.localTokenTracker,
                            remoteTracker: sessionStore.remoteTokenTracker
                        )
                    }

                    // ── 展开的活动日志 ──
                    if localCardExpanded, let session = sessionStore.effectiveLocalSession {
                        DualSourceActivitySection(
                            session: session,
                            creatureType: .hermitCrab
                        )
                    }
                    if remoteCardExpanded, let session = sessionStore.effectiveRemoteSession {
                        DualSourceActivitySection(
                            session: session,
                            creatureType: .crawfish
                        )
                    }

                    // ── 足迹 ──
                    let history = SessionHistory.shared.records
                    if !history.isEmpty {
                        sectionDivider

                        HStack(spacing: DS.Space.xs) {
                            DS.sectionLabel(L10n.s("dash.footprints"))

                            // 今日/昨日汇总 + 趋势箭头
                            let today = SessionHistory.shared.todayTotalTokens
                            let yesterday = SessionHistory.shared.yesterdayTotalTokens
                            if today > 0 {
                                Text(TokenTracker.formatTokens(today))
                                    .font(DS.Font.monoSmall)
                                    .foregroundColor(DS.TextColor.secondary)
                                if let trend = SessionHistory.shared.dayOverDayTrend {
                                    Text(trend > 0.1 ? "↑" : trend < -0.1 ? "↓" : "→")
                                        .font(DS.Font.monoSmall)
                                        .foregroundColor(trend > 0.1 ? DS.Semantic.warning : trend < -0.1 ? DS.Semantic.success : DS.TextColor.tertiary)
                                }
                            } else if yesterday > 0 {
                                // 今日无数据时显示昨日汇总
                                Text("\(L10n.s("time.yesterday")) \(TokenTracker.formatTokens(yesterday))")
                                    .font(DS.Font.monoSmall)
                                    .foregroundColor(DS.TextColor.tertiary)
                            }

                            Spacer()
                            DashboardPulseView(
                                snapshot: GatewayDashboard.shared.snapshot,
                                historyCount: history.count,
                                isLoading: GatewayDashboard.shared.isLoading
                            )
                        }

                        ForEach(history.prefix(20)) { record in
                            HistoryRowView(
                                record: record,
                                expandedRecordId: $expandedRecordId
                            )
                        }
                    } else if sessionStore.activeSessionCount == 0 {
                        // Empty state
                        emptyState
                    }
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.sm)
            }
            .frame(maxHeight: .infinity)

            // 输入框 — 固定底部
            SpotlightInputView(
                onSend: { message in
                    CommandSender.shared.sendChat(message: message)
                }
            )
        }
        .task {
            await GatewayDashboard.shared.refreshIfNeeded()
        }
    }

    // MARK: - Gateway Status

    private var gatewayStatusView: some View {
        let (color, label): (Color, String) = switch GatewayClient.shared.state {
        case .connected:      (.green, "已连接")
        case .connecting:     (.yellow, "连接中")
        case .authenticating: (.orange, "认证中")
        case .disconnected:   (.red, "未连接")
        }
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(DS.Font.caption).foregroundColor(DS.TextColor.tertiary)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "water.waves")
                .font(.system(size: 24))
                .foregroundColor(DS.Semantic.info.opacity(0.4))
            Text(L10n.s("dash.waiting"))
                .font(DS.Font.subhead)
                .foregroundColor(DS.TextColor.secondary)
            Text(L10n.s("dash.waitingDesc"))
                .font(DS.Font.body)
                .foregroundColor(DS.TextColor.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }

    // MARK: - Settings View

    @ViewBuilder
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(L10n.s("settings.title"))
                .font(DS.Font.title)
                .foregroundColor(DS.TextColor.primary)
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.sm)

            sectionDivider

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    // ── Connection Section ──
                    DS.sectionLabel(L10n.s("settings.connection"))

                    settingRow(title: L10n.s("settings.mode"), value: AppSettings.roleName(AppSettings.setupRole))
                    settingRow(title: L10n.s("settings.method"),
                               value: AppSettings.setupRole == .local ? "Unix Socket" : "TCP")
                    settingRow(title: L10n.s("settings.port"), value: "TCP:\(SocketServer.tcpPort)")

                    if !AppSettings.rockpileHost.isEmpty {
                        settingRow(title: L10n.s("settings.remoteHost"), value: AppSettings.rockpileHost)
                    }
                    if let ip = SetupManager.getLocalIP() {
                        settingRow(title: L10n.s("settings.localIP"), value: ip)
                    }

                    sectionDividerInline

                    // ── Local O₂ ──
                    let localProvider = AIProviderDetector.detectLocalProvider()
                    DS.sectionLabel(L10n.s("settings.localO2"))

                    providerBadge(localProvider, accent: DS.Semantic.localAccent)

                    oxygenModeSelector(
                        mode: $localOxygenMode,
                        onChanged: { AppSettings.localOxygenMode = $0 }
                    )

                    // 订阅模式自动使用推荐配额，仅按量模式显示容量选择
                    if localOxygenMode == "paid" {
                        capacitySelector(
                            capacity: $localTankCapacity,
                            onChanged: { AppSettings.localOxygenTankCapacity = $0 },
                            accentColor: DS.Semantic.localAccent
                        )
                    } else {
                        settingRow(title: L10n.s("settings.dailyQuota"), value: TokenTracker.formatTokens(localProvider.recommendedCapacity) + " " + L10n.s("settings.auto"))
                    }

                    sectionDividerInline

                    // ── Remote O₂ ──
                    let remoteProvider = AIProviderDetector.detectRemoteProvider()
                    DS.sectionLabel(L10n.s("settings.remoteO2"))

                    providerBadge(remoteProvider, accent: DS.Semantic.remoteAccent)

                    oxygenModeSelector(
                        mode: $remoteOxygenMode,
                        onChanged: { AppSettings.remoteOxygenMode = $0 }
                    )

                    // 订阅模式自动使用推荐配额，仅按量模式显示容量选择
                    if remoteOxygenMode == "paid" {
                        capacitySelector(
                            capacity: $remoteTankCapacity,
                            onChanged: { AppSettings.remoteOxygenTankCapacity = $0 },
                            accentColor: DS.Semantic.remoteAccent
                        )
                    } else {
                        settingRow(title: L10n.s("settings.dailyQuota"), value: TokenTracker.formatTokens(remoteProvider.recommendedCapacity) + " " + L10n.s("settings.auto"))
                    }

                    sectionDividerInline

                    // ── Language Section ──
                    DS.sectionLabel(L10n.s("settings.language"))

                    HStack(spacing: DS.Space.sm) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            modeButton(
                                "\(lang.flag) \(lang.displayName)",
                                isActive: L10n.language == lang,
                                activeColor: DS.Semantic.accent.opacity(0.3)
                            ) {
                                AppSettings.appLanguage = lang.rawValue
                                // Force UI refresh
                                NotificationCenter.default.post(name: .rockpileShouldRefreshUI, object: nil)
                            }
                        }
                    }

                    sectionDividerInline

                    // ── Launch at Login ──
                    DS.sectionLabel(L10n.s("settings.startup"))

                    Toggle(isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.isEnabled = $0 }
                    )) {
                        Text(L10n.s("settings.launchAtLogin"))
                            .font(DS.Font.secondary)
                            .foregroundColor(DS.TextColor.primary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(DS.Semantic.accent)

                    sectionDividerInline

                    // ── Actions Section ──
                    DS.sectionLabel(L10n.s("settings.actions"))

                    Button(action: {
                        PluginInstaller.installIfNeeded()
                        reinstallMessage = AppSettings.setupRole == .monitor
                            ? L10n.s("settings.reinstallNA")
                            : L10n.s("settings.reinstallDone")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            reinstallMessage = nil
                        }
                    }) {
                        Text(L10n.s("settings.reinstallPlugin"))
                    }
                    .font(DS.Font.subhead)
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Semantic.accent)

                    if let msg = reinstallMessage {
                        Text(msg)
                            .font(DS.Font.secondary)
                            .foregroundColor(DS.TextColor.secondary)
                            .transition(.opacity)
                    }

                    Button(L10n.s("settings.resetSettings")) {
                        AppSettings.resetSetup()
                        NotificationCenter.default.post(
                            name: .rockpileShouldResetSetup, object: nil)
                    }
                    .font(DS.Font.subhead)
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Semantic.warning)

                    Button(L10n.s("settings.quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(DS.Font.subhead)
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Semantic.danger)
                }
                .padding(.horizontal, DS.Space.md)
            }
        }
    }

    // MARK: - O₂ Settings Components

    @ViewBuilder
    private func oxygenModeSelector(mode: Binding<String>, onChanged: @escaping (String) -> Void) -> some View {
        HStack(spacing: DS.Space.sm) {
            modeButton(L10n.s("settings.claudeQuota"), isActive: mode.wrappedValue == "claude",
                        activeColor: DS.Semantic.info.opacity(0.3)) {
                mode.wrappedValue = "claude"
                onChanged("claude")
            }
            modeButton(L10n.s("settings.paidUsage"), isActive: mode.wrappedValue == "paid",
                        activeColor: DS.Semantic.toolCall.opacity(0.3)) {
                mode.wrappedValue = "paid"
                onChanged("paid")
            }
        }
    }

    @ViewBuilder
    private func capacitySelector(capacity: Binding<Int>, onChanged: @escaping (Int) -> Void, accentColor: Color) -> some View {
        settingRow(title: L10n.s("settings.bottleCapacity"), value: TokenTracker.formatTokens(capacity.wrappedValue) + " tokens")

        HStack(spacing: DS.Space.sm) {
            ForEach([500_000, 1_000_000, 2_000_000, 5_000_000], id: \.self) { cap in
                modeButton(TokenTracker.formatTokens(cap),
                           isActive: capacity.wrappedValue == cap,
                           activeColor: accentColor.opacity(0.3),
                           font: DS.Font.mono) {
                    capacity.wrappedValue = cap
                    onChanged(cap)
                }
            }
        }
    }

    // MARK: - Reusable Components

    private var sectionDivider: some View {
        Divider()
            .background(DS.Surface.divider)
    }

    private var sectionDividerInline: some View {
        Divider()
            .background(Color.white.opacity(DS.Opacity.ghost))
    }

    private func modeButton(
        _ label: String,
        isActive: Bool,
        activeColor: Color,
        font: SwiftUI.Font = DS.Font.secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(label, action: action)
            .font(font)
            .buttonStyle(.plain)
            .foregroundColor(isActive ? .white : DS.TextColor.secondary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(isActive ? activeColor : DS.Surface.raised)
            )
    }

    @ViewBuilder
    private func providerBadge(_ provider: AIProvider, accent: Color) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text("\(L10n.s("settings.detected")): \(L10n.s(provider.displayNameKey))")
                .font(DS.Font.mono)
                .foregroundColor(DS.TextColor.primary)
            if !provider.billingLabelKey.isEmpty {
                Text(L10n.s(provider.billingLabelKey))
                    .font(DS.Font.monoSmall)
                    .foregroundColor(accent)
                    .padding(.horizontal, DS.Space.xs)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(DS.Opacity.ghost))
                    )
            }
        }
    }

    private func settingRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title)
                .font(DS.Font.body)
                .foregroundColor(DS.TextColor.secondary)
            Text(value)
                .font(DS.Font.mono)
                .foregroundColor(DS.TextColor.primary)
        }
    }
}
