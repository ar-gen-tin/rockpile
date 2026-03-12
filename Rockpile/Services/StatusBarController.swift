import AppKit
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "StatusBar")

extension Notification.Name {
    static let rockpileShouldShowSettings = Notification.Name("rockpileShouldShowSettings")
}

/// Manages the macOS menu bar status item (crayfish icon + dropdown menu).
/// Menu rebuilds on open via NSMenuDelegate (no polling timer).
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    /// Icon cache — avoid re-rendering when sprite name hasn't changed (CodexBar IconCacheStore 简化版)
    private var cachedIconName: String?
    private var cachedIcon: NSImage?

    /// 标题刷新计时器 — 30 秒更新 O₂% 显示
    private var titleTimer: Timer?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let icon = createMenuBarIcon() {
            item.button?.image = icon
        } else {
            item.button?.title = "🦞"
        }
        item.button?.toolTip = "Rockpile"
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // 定时更新标题 O₂%
        updateTitle()
        titleTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }

        logger.info("Status bar item created")
    }

    // MARK: - Title Update

    /// 更新状态栏标题: icon + O₂%（优先显示活跃会话，空闲时显示日用量）
    private func updateTitle() {
        guard let item = statusItem else { return }
        let sessionStore = StateMachine.shared.sessionStore
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        if let session = sessionStore.effectiveSession {
            // 活跃会话: 显示 O₂%
            let o2 = session.tokenTracker.oxygenPercent
            item.button?.attributedTitle = NSAttributedString(string: " \(o2)%", attributes: attrs)
        } else {
            // 空闲: 显示两个 tracker 中较低的 O₂ (有数据时)
            let local = sessionStore.localTokenTracker
            let remote = sessionStore.remoteTokenTracker
            if local.hasUsageData || remote.hasUsageData {
                let minO2 = min(local.oxygenPercent, remote.oxygenPercent)
                item.button?.attributedTitle = NSAttributedString(string: " \(minO2)%", attributes: attrs)
            } else {
                item.button?.title = ""
            }
        }
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        // Called synchronously on main thread before menu displays
        nonisolated(unsafe) let m = menu
        MainActor.assumeIsolated {
            self.updateIcon()
            self.updateTitle()
            m.removeAllItems()
            let freshMenu = self.buildMenu()
            while let item = freshMenu.items.first {
                freshMenu.removeItem(item)
                m.addItem(item)
            }
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let sessionStore = StateMachine.shared.sessionStore

        // ── Status ──
        let count = sessionStore.activeSessionCount
        if count > 0, let session = sessionStore.effectiveSession {
            let stateText = session.state.displayName
            let statusItem = NSMenuItem(
                title: "● \(stateText)",
                action: nil, keyEquivalent: ""
            )
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            let countItem = NSMenuItem(
                title: "\(count) \(L10n.s("menu.activeSessions"))",
                action: nil, keyEquivalent: ""
            )
            countItem.isEnabled = false
            menu.addItem(countItem)

            // O₂ level
            let tracker = session.tokenTracker
            let o2 = tracker.oxygenLevel
            let o2Pct = Int(o2 * 100)
            let o2Text = o2Pct > 0 ? "O\u{2082}  \(o2Pct)%" : "O\u{2082}  \(L10n.s("menu.depleted"))"
            let o2Item = NSMenuItem(title: o2Text, action: nil, keyEquivalent: "")
            o2Item.isEnabled = false
            menu.addItem(o2Item)

            // Burn rate + ETA (仅活跃消耗时显示)
            if tracker.burnRate > 0 {
                var rateStr = "\(tracker.velocityArrow)\(tracker.burnRateText)"
                if let eta = tracker.etaText {
                    rateStr += "  \(eta)"
                }
                let rateItem = NSMenuItem(title: rateStr, action: nil, keyEquivalent: "")
                rateItem.isEnabled = false
                menu.addItem(rateItem)
            }
        } else {
            let idle = NSMenuItem(title: L10n.s("menu.noSession"), action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)

            // 空闲时显示双源 O₂ 概览
            let localTracker = sessionStore.localTokenTracker
            let remoteTracker = sessionStore.remoteTokenTracker
            if localTracker.hasUsageData || remoteTracker.hasUsageData {
                let localO2 = localTracker.oxygenPercent
                let remoteO2 = remoteTracker.oxygenPercent
                let o2Summary = NSMenuItem(
                    title: "🐚 O\u{2082} \(localO2)%  🦞 O\u{2082} \(remoteO2)%",
                    action: nil, keyEquivalent: ""
                )
                o2Summary.isEnabled = false
                menu.addItem(o2Summary)
            }
        }

        menu.addItem(.separator())

        // ── Connection Info ──
        let modeText = AppSettings.roleName(AppSettings.setupRole)
        let modeItem = NSMenuItem(title: modeText, action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)

        if let ip = SetupManager.getLocalIP() {
            let code = SetupManager.ipToCode(ip)
            let pairItem = NSMenuItem(title: "\(L10n.s("menu.pairCode")): \(code)", action: nil, keyEquivalent: "")
            pairItem.isEnabled = false
            menu.addItem(pairItem)

            let ipItem = NSMenuItem(title: "IP: \(ip)", action: nil, keyEquivalent: "")
            ipItem.isEnabled = false
            menu.addItem(ipItem)
        }

        menu.addItem(.separator())

        // ── Launch at Login ──
        let launchItem = NSMenuItem(
            title: L10n.s("menu.launchAtLogin"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        // ── Actions ──
        let settingsItem = NSMenuItem(
            title: L10n.s("menu.settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let logItem = NSMenuItem(
            title: L10n.s("menu.exportLog"),
            action: #selector(exportLogs),
            keyEquivalent: "l"
        )
        logItem.target = self
        menu.addItem(logItem)

        let openLogItem = NSMenuItem(
            title: L10n.s("menu.openLogFolder"),
            action: #selector(openLogFolder),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

        menu.addItem(.separator())

        // ── Version ──
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Rockpile v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(
            title: L10n.s("menu.quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func openSettings() {
        PanelManager.shared.expand()
        NotificationCenter.default.post(name: .rockpileShouldShowSettings, object: nil)
    }

    @objc private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "rockpile-\(Int(Date().timeIntervalSince1970)).log"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                EventLogger.shared.exportLogs(to: url)
            }
        }
    }

    @objc private func openLogFolder() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Rockpile")
        NSWorkspace.shared.open(logDir)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon

    /// Update menu bar icon based on current session state.
    /// Uses sprite name cache to skip redundant NSImage rendering.
    private func updateIcon() {
        guard let item = statusItem else { return }
        let name = currentIconSpriteName
        if name == cachedIconName, let cached = cachedIcon {
            item.button?.image = cached
            return
        }
        if let icon = createMenuBarIcon() {
            cachedIconName = name
            cachedIcon = icon
            item.button?.image = icon
        }
    }

    /// Determine the sprite sheet name matching current effective session state
    private var currentIconSpriteName: String {
        guard let session = StateMachine.shared.sessionStore.effectiveSession else {
            return "idle_neutral"
        }
        let task = session.state.task
        let emotion = session.state.emotion
        // Map to sprite sheet: "{task}_{emotion}" with fallback to neutral
        let name = "\(task.rawValue)_\(emotion.rawValue)"
        if NSImage(named: name) != nil { return name }
        // Fallback: task_neutral
        let fallback = "\(task.rawValue)_neutral"
        if NSImage(named: fallback) != nil { return fallback }
        return "idle_neutral"
    }

    /// Extract the crayfish silhouette from the sprite sheet as a macOS template icon.
    /// Template icons are black-on-transparent; macOS automatically renders them
    /// in the correct color (white on dark menu bar, dark on light menu bar).
    private func createMenuBarIcon() -> NSImage? {
        guard let spriteSheet = NSImage(named: currentIconSpriteName),
              let rep = spriteSheet.representations.first else { return nil }

        let frameW = CGFloat(rep.pixelsWide) / 12  // 12 animation frames
        let frameH = CGFloat(rep.pixelsHigh)
        let sourceRect = NSRect(x: 0, y: 0, width: frameW, height: frameH)

        // Draw the first sprite frame at menu bar size
        let iconSize = NSSize(width: 18, height: 18)
        let icon = NSImage(size: iconSize, flipped: false) { rect in
            spriteSheet.draw(in: rect, from: sourceRect,
                             operation: .sourceOver, fraction: 1.0)
            return true
        }
        // isTemplate = true → macOS controls the color to match other menu bar icons
        icon.isTemplate = true
        return icon
    }
}
