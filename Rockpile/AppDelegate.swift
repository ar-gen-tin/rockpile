import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var menuBarPopover: NSPopover?
    private var onboardingWindow: NSWindow?
    private let windowHeight: CGFloat = 500
    private let statusBar = StatusBarController()

    /// Whether the current screen has a hardware notch
    private var hasNotch: Bool {
        let screen = ScreenSelector.shared.selectedScreen
            ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.hasNotch ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Zero-config: auto-setup on first launch (no onboarding wizard)
        autoSetupIfNeeded()

        if AppSettings.setupRole == .host {
            launchHostOnlyMode()
        } else {
            launchNotchMode()
        }

        // Observe reset request (from Settings → Reset Setup)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResetSetup),
            name: .rockpileShouldResetSetup,
            object: nil
        )
    }

    @objc private func handleResetSetup() {
        // Tear down current UI
        notchPanel?.orderOut(nil)
        notchPanel = nil
        // Re-launch onboarding
        launchOnboarding()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Auto Setup (Zero-Config)

    /// First-launch auto-configuration — replaces the 4-step onboarding wizard.
    /// Detects environment, installs hooks, sets defaults.
    private func autoSetupIfNeeded() {
        guard !AppSettings.setupCompleted else {
            // Already set up — just ensure hooks are current
            AIProviderDetector.autoConfigureIfNeeded()
            HookInstaller.installIfNeeded()
            // Update version stamp (skip re-onboarding on version update)
            if AppSettings.setupCompletedVersion != AppSettings.currentAppVersion {
                AppSettings.setupCompletedVersion = AppSettings.currentAppVersion
            }
            return
        }

        // Detect system language
        let preferredLang = Locale.preferredLanguages.first ?? "en"
        if preferredLang.hasPrefix("zh") {
            AppSettings.appLanguage = "zh"
        } else if preferredLang.hasPrefix("ja") {
            AppSettings.appLanguage = "ja"
        } else {
            AppSettings.appLanguage = "en"
        }

        // Default to local mode
        AppSettings.setupRole = .local

        // Auto-detect AI provider and configure O₂
        AIProviderDetector.autoConfigureIfNeeded()

        // Override O₂ defaults for Claude subscription
        AppSettings.localOxygenMode = "claude"
        AppSettings.localOxygenTankCapacity = 300_000

        // Install bash hooks
        HookInstaller.installIfNeeded()

        // Mark setup complete
        AppSettings.setupCompleted = true
    }

    // MARK: - Onboarding (manual reconfigure only)

    private func launchOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)

        let isUpdate = AppSettings.isVersionUpdate
        let onboardingView = OnboardingView(isUpdate: isUpdate) { [weak self] in
            Task { @MainActor in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil

                if AppSettings.setupRole == .host {
                    self?.launchHostOnlyMode()
                } else {
                    self?.launchNotchMode()
                }
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rockpile Setup"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        self.onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Notch Mode (local / monitor)

    private func launchNotchMode() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if hasNotch {
            setupNotchWindow()
            observeScreenChanges()
        }
        startServices()
        statusBar.setup(showPopover: !hasNotch)
    }

    // MARK: - Host-Only Mode

    private func launchHostOnlyMode() {
        NSApplication.shared.setActivationPolicy(.accessory)
        PluginInstaller.installIfNeeded()
        SocketServer.shared.start { event, source in
            Task { @MainActor in
                StateMachine.shared.handleEvent(event, source: source)
            }
        }
        statusBar.setup()
    }

    // MARK: - Services

    private func startServices() {
        HookInstaller.installIfNeeded()
        PluginInstaller.installIfNeeded()  // Legacy plugin support
        SocketServer.shared.start { event, source in
            Task { @MainActor in
                StateMachine.shared.handleEvent(event, source: source)
            }
        }
        // Connect to Gateway WebSocket only in monitor mode (local has no Gateway server)
        if AppSettings.setupRole == .monitor {
            GatewayClient.shared.connect()
        }
        // Start cross-creature interaction scheduling
        InteractionCoordinator.shared.startScheduling()
        // Start Usage API polling (if configured)
        UsageQueryService.shared.startPolling()
        // Register service status providers and start polling
        let statusMonitor = ServiceStatusMonitor.shared
        statusMonitor.register(AtlassianStatusProvider())
        statusMonitor.register(XAIStatusProvider())
        statusMonitor.register(GoogleCloudStatusProvider())
        statusMonitor.startPolling()
        // Register data providers
        ProviderRegistry.shared.register(SocketServer.shared)
        ProviderRegistry.shared.register(GatewayClient.shared)
    }

    // MARK: - Notch Window

    private func setupNotchWindow() {
        ScreenSelector.shared.refreshScreens()
        guard let screen = ScreenSelector.shared.selectedScreen
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        PanelManager.shared.updateGeometry(for: screen)

        let panel = NotchPanel(frame: windowFrame(for: screen))

        let contentView = NotchContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let hitTestView = NotchHitTestView()
        hitTestView.panelManager = PanelManager.shared
        hitTestView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: hitTestView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
        ])

        panel.contentView = hitTestView
        panel.orderFrontRegardless()

        self.notchPanel = panel
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func repositionWindow() {
        guard let panel = notchPanel else { return }
        ScreenSelector.shared.refreshScreens()
        guard let screen = ScreenSelector.shared.selectedScreen
                ?? NSScreen.main ?? NSScreen.screens.first else { return }

        PanelManager.shared.updateGeometry(for: screen)
        panel.setFrame(windowFrame(for: screen), display: true)
    }

    private func windowFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }
}
