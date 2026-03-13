import SwiftUI

/// NotchContentView — 主窗口内容，嵌入 macOS Notch 形状中
///
/// 布局结构（展开时）：
/// ┌─────────────────────────────┐
/// │  headerRow (Notch 高度)      │  ← 标题栏 + 精灵缩略图
/// │  PondView (30%)              │  ← 水面 + 双生物动画
/// │  ExpandedPanelView (70%)     │  ← 双源 Dashboard（纯黑背景）
/// └─────────────────────────────┘
///
/// 收起时仅显示 headerRow + 精灵缩略图（寄居蟹/小龙虾）。
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchContentView: View {
    var stateMachine: StateMachine = .shared
    var panelManager: PanelManager = .shared
    @State private var showingSettings = false
    @State private var isActivityCollapsed = false
    @State private var languageRefresh = 0

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    private var notchSize: CGSize { panelManager.notchSize }
    private var isExpanded: Bool { panelManager.isExpanded }

    private var panelAnimation: Animation {
        isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }

    private var sideWidth: CGFloat {
        max(0, notchSize.height - 12) + 24
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    /// Full expanded panel content height (excluding notch header)
    private var expandedPanelHeight: CGFloat {
        let fullHeight = ClawConstants.expandedPanelSize.height - notchSize.height - 24
        let collapsedHeight: CGFloat = 155
        return isActivityCollapsed ? collapsedHeight : fullHeight
    }

    /// Pond visible height (40% — 生物观赏区，海底沙地 + 双生物 + 互动)
    private var pondVisibleHeight: CGFloat {
        expandedPanelHeight * 0.40
    }

    /// Text panel height (60% — 核心信息面板：状态 / O₂ / 活动 / 足迹)
    private var textPanelHeight: CGFloat {
        expandedPanelHeight * 0.60
    }

    var body: some View {
        VStack(spacing: 0) {
            notchLayout
        }
        .padding(.horizontal, isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom)
        .padding(.bottom, isExpanded ? 12 : 0)
        .background(Color.black)
        .clipShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        ))
        .shadow(
            color: isExpanded ? .black.opacity(0.7) : .clear,
            radius: 6
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(panelAnimation, value: isExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .rockpileShouldCollapse)) { _ in
            panelManager.collapse()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rockpileShouldShowSettings)) { _ in
            showingSettings = true
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                showingSettings = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rockpileShouldRefreshUI)) { _ in
            languageRefresh += 1
        }
        .id(languageRefresh)
    }

    @ViewBuilder
    private var notchLayout: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .frame(height: notchSize.height)

                if isExpanded {
                    let panelWidth = ClawConstants.expandedPanelSize.width - 48

                    // ── Pond area (water + crayfish only, NO text overlay) ──
                    if !showingSettings {
                        PondView(
                            sessions: sessionStore.sortedSessions,
                            selectedSessionId: sessionStore.selectedSessionId,
                            oxygenLevel: sessionStore.effectiveSession?.tokenTracker.oxygenLevel ?? 1.0,
                            tokenTracker: sessionStore.globalTokenTracker
                        )
                        .frame(width: panelWidth, height: pondVisibleHeight)
                        .clipped()
                    }

                    // ── Text panel (solid black background, all text here) ──
                    ExpandedPanelView(
                        sessionStore: sessionStore,
                        showingSettings: $showingSettings,
                        isActivityCollapsed: $isActivityCollapsed
                    )
                    .frame(
                        width: panelWidth,
                        height: showingSettings ? expandedPanelHeight : textPanelHeight
                    )
                    .background(Color.black)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
                }
            }

            if isExpanded {
                HStack(spacing: 8) {
                    // macOS 风格红黄绿状态灯
                    trafficLights
                    Spacer()
                    headerButton(icon: panelManager.isPinned ? "pin.fill" : "pin") {
                        panelManager.togglePin()
                    }
                    .accessibilityLabel(panelManager.isPinned ? L10n.s("header.unpin") : L10n.s("header.pin"))
                    headerButton(icon: "gearshape") {
                        showingSettings.toggle()
                    }
                    .accessibilityLabel(L10n.s("header.settings"))
                    headerButton(icon: "xmark") {
                        panelManager.collapse()
                    }
                    .accessibilityLabel(L10n.s("header.close"))
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)
                .frame(width: ClawConstants.expandedPanelSize.width - 48)
            }
        }
    }

    /// O₂ 是否处于低氧警告状态 (任一生物 <30%)
    private var isLowOxygen: Bool {
        sessionStore.localTokenTracker.isLowOxygen || sessionStore.remoteTokenTracker.isLowOxygen
    }

    /// O₂ 是否有任一生物死亡 (0%)
    private var hasDeadCreature: Bool {
        sessionStore.localTokenTracker.isDead || sessionStore.remoteTokenTracker.isDead
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // 左侧：⚠️ O₂ 预警（优先）或 📱 远程活动指示器
            headerLeftIndicator
                .frame(width: sideWidth)
                .opacity(isExpanded ? 0 : 1)
                .animation(.none, value: isExpanded)

            Color.clear
                .frame(width: notchSize.width - cornerRadiusInsets.closed.top)

            headerSprites
                .offset(x: 15, y: -2)
                .frame(width: sideWidth)
                .opacity(isExpanded ? 0 : 1)
                .animation(.none, value: isExpanded)
        }
    }

    /// 左侧指示器：⚠️ O₂ 预警优先于 📱 远程活动
    @ViewBuilder
    private var headerLeftIndicator: some View {
        if isLowOxygen || hasDeadCreature {
            headerOxygenWarning
        } else {
            headerRemoteIndicator
        }
    }

    /// ⚠️ O₂ 低氧/死亡预警指示器
    @ViewBuilder
    private var headerOxygenWarning: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: false)) { timeline in
            let blinkOn = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0

            HStack(spacing: DS.Space.xxs) {
                Text(hasDeadCreature ? "💀" : "⚠️")
                    .font(DS.Font.tiny)
                Text(hasDeadCreature ? L10n.s("o2.ko") : L10n.s("o2.lowOxygen"))
                    .font(DS.Font.monoBold)
                    .foregroundColor(hasDeadCreature ? DS.Semantic.danger : DS.Semantic.warning)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill((hasDeadCreature ? DS.Semantic.danger : DS.Semantic.warning).opacity(DS.Opacity.ghost))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(
                                (hasDeadCreature ? DS.Semantic.danger : DS.Semantic.warning).opacity(DS.Opacity.tertiary),
                                lineWidth: 0.5
                            )
                    )
            )
            .opacity(blinkOn ? 1 : 0.5)
            .offset(x: -10)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// 折叠态 headerRow 左侧的远程活动指示器
    @ViewBuilder
    private var headerRemoteIndicator: some View {
        let tracker = RemoteActivityTracker.shared
        if tracker.pendingCount > 0 {
            let label = tracker.pendingCount > 9 ? "+N" : "+\(tracker.pendingCount)"
            HStack(spacing: DS.Space.xxs) {
                Text("📱")
                    .font(DS.Font.tiny)
                Text(label)
                    .font(DS.Font.monoBold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Surface.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(DS.TextColor.muted, lineWidth: 0.5)
                    )
            )
            .offset(x: -10)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: tracker.pendingCount)
        }
    }

    @ViewBuilder
    private var headerSprites: some View {
        let spriteSize = min(notchSize.height - 4, 28)
        HStack(spacing: -4) {
            // Primary: prefer local hermit crab, fallback to crawfish
            if let localSession = sessionStore.effectiveLocalSession {
                HermitCrabSpriteView(
                    state: localSession.state,
                    isSelected: true,
                    size: spriteSize
                )
            } else {
                let crawfishSession = sessionStore.effectiveRemoteSession ?? sessionStore.sortedSessions.first
                CrawfishSpriteView(
                    state: crawfishSession?.state ?? .idle,
                    isSelected: true,
                    size: spriteSize
                )
            }

            // Secondary: crawfish if both local + remote exist
            if let remoteSession = sessionStore.effectiveRemoteSession,
               sessionStore.effectiveLocalSession != nil {
                CrawfishSpriteView(
                    state: remoteSession.state,
                    isSelected: false,
                    size: spriteSize * 0.85
                )
                .opacity(0.8)
            }
        }
    }

    /// 连接状态：green=已连接, yellow=中间态(发送中/排队), red=断开
    private enum ConnectionLevel {
        case connected, intermediate, disconnected
    }

    private var connectionLevel: ConnectionLevel {
        // Gateway WebSocket state takes priority
        switch GatewayClient.shared.state {
        case .connected:
            return .connected
        case .connecting, .authenticating:
            return .intermediate
        case .disconnected:
            // Fallback: check if we have plugin sessions
            if sessionStore.activeSessionCount > 0 { return .connected }
            switch CommandSender.shared.lastResult {
            case .sending, .queued:
                return .intermediate
            default:
                return .disconnected
            }
        }
    }

    @ViewBuilder
    private var trafficLights: some View {
        let level = connectionLevel
        HStack(spacing: 4) {
            trafficDot(color: DS.Semantic.danger, active: level == .disconnected)
            trafficDot(color: DS.Semantic.warning, active: level == .intermediate)
            trafficDot(color: DS.Semantic.success, active: level == .connected)
        }
        .animation(.easeInOut(duration: 0.3), value: level)
    }

    private func trafficDot(color: Color, active: Bool) -> some View {
        Circle()
            .fill(color.opacity(active ? 1.0 : 0.2))
            .frame(width: 7, height: 7)
    }

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.subhead)
                .foregroundColor(DS.TextColor.secondary)
                .frame(width: DS.Space.xl, height: DS.Space.xl)
        }
        .buttonStyle(.plain)
    }
}
