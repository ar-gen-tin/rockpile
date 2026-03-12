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

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let icon = createMenuBarIcon() {
            item.button?.image = icon
        } else {
            item.button?.title = "🦞"
        }
        item.button?.toolTip = "Rockpile"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        logger.info("Status bar item created")
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        // Called synchronously on main thread before menu displays
        nonisolated(unsafe) let m = menu
        MainActor.assumeIsolated {
            self.updateIcon()
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
            let o2 = session.tokenTracker.oxygenLevel
            let o2Pct = Int(o2 * 100)
            let o2Text = o2Pct > 0 ? "O\u{2082}  \(o2Pct)%" : "O\u{2082}  \(L10n.s("menu.depleted"))"
            let o2Item = NSMenuItem(title: o2Text, action: nil, keyEquivalent: "")
            o2Item.isEnabled = false
            menu.addItem(o2Item)
        } else {
            let idle = NSMenuItem(title: L10n.s("menu.noSession"), action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)
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

    /// Update menu bar icon based on current session state
    private func updateIcon() {
        guard let item = statusItem else { return }
        if let icon = createMenuBarIcon() {
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
