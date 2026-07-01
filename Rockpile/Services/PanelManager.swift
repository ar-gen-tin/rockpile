import AppKit
import Observation

enum ClawConstants {
    static let expandedPanelSize = RC.Panel.expandedSize
    static let expandedPanelHorizontalPadding: CGFloat = RC.Panel.expandedHorizontalPadding
}

extension Notification.Name {
    static let rockpileShouldCollapse = Notification.Name("rockpileShouldCollapse")
    static let rockpileShouldResetSetup = Notification.Name("rockpileShouldResetSetup")
    static let rockpileShouldRefreshUI = Notification.Name("rockpileShouldRefreshUI")
}

@MainActor
@Observable
final class PanelManager {
    static let shared = PanelManager()

    private(set) var isExpanded = false
    private(set) var isPinned = false
    private(set) var notchSize: CGSize = .zero
    private(set) var notchRect: CGRect = .zero
    private(set) var panelRect: CGRect = .zero
    private var screenHeight: CGFloat = 0

    private var mouseDownMonitor: EventMonitor?

    private init() {
        setupEventMonitors()
    }

    func updateGeometry(for screen: NSScreen) {
        let newNotchSize = screen.notchSize
        let screenFrame = screen.frame

        notchSize = newNotchSize

        let notchCenterX = screenFrame.origin.x + screenFrame.width / 2
        let sideWidth = max(0, newNotchSize.height - 12) + 24
        let notchTotalWidth = newNotchSize.width + sideWidth * 2  // 左侧指示器 + 右侧精灵

        notchRect = CGRect(
            x: notchCenterX - notchTotalWidth / 2,
            y: screenFrame.maxY - newNotchSize.height,
            width: notchTotalWidth,
            height: newNotchSize.height
        )

        let panelSize = ClawConstants.expandedPanelSize
        let panelWidth = panelSize.width + ClawConstants.expandedPanelHorizontalPadding
        panelRect = CGRect(
            x: notchCenterX - panelWidth / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelWidth,
            height: panelSize.height
        )

        screenHeight = screenFrame.height
    }

    private func setupEventMonitors() {
        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDown()
            }
        }
        mouseDownMonitor?.start()
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        if isExpanded {
            if !isPinned && !panelRect.contains(location) {
                collapse()
            }
        } else {
            if notchRect.contains(location) {
                expand()
            }
        }
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
    }

    func toggle() {
        if isExpanded { collapse() } else { expand() }
    }

    func togglePin() {
        isPinned.toggle()
    }
}
