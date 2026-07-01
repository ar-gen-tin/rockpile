import AppKit

/// A borderless, transparent panel positioned at the MacBook notch area
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        level = .mainMenu + 3
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Snapshot of the frontmost app before we became key, for focus restoration
    private static var previousApp: NSRunningApplication?

    override func becomeKey() {
        // Snapshot current frontmost app before we steal focus
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            Self.previousApp = frontmost
        }
        super.becomeKey()
    }

    /// Restore focus to the app that was active before the input box was used
    static func returnFocusToPreviousApp() {
        if let prev = previousApp {
            prev.activate()
            previousApp = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NotificationCenter.default.post(name: .rockpileShouldCollapse, object: nil)
        }
    }
}
