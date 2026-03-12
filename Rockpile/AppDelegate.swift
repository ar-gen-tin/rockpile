import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var onboardingWindow: NSWindow?
    private let windowHeight: CGFloat = 500
    private let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auto-detect AI provider and configure O₂ defaults on first launch
        AIProviderDetector.autoConfigureIfNeeded()

        if AppSettings.needsOnboarding {
            launchOnboarding()
        } else if AppSettings.setupRole == .host {
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

    // MARK: - Onboarding

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
        setupNotchWindow()
        observeScreenChanges()
        startServices()
        statusBar.setup()
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
        // Connect to Gateway WebSocket (dashboard data + reverse commands)
        GatewayClient.shared.connect()
        statusBar.setup()
    }

    // MARK: - Services

    private func startServices() {
        PluginInstaller.installIfNeeded()
        SocketServer.shared.start { event, source in
            Task { @MainActor in
                StateMachine.shared.handleEvent(event, source: source)
            }
        }
        // Connect to Rockpile Gateway WebSocket for reverse commands
        GatewayClient.shared.connect()
        // Start cross-creature interaction scheduling
        InteractionCoordinator.shared.startScheduling()
        // Start Usage API polling (if configured)
        UsageQueryService.shared.startPolling()
    }

    // MARK: - Notch Window

    private func setupNotchWindow() {
        ScreenSelector.shared.refreshScreens()
        guard let screen = ScreenSelector.shared.selectedScreen else { return }
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
        guard let screen = ScreenSelector.shared.selectedScreen else { return }

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
