import AppKit

extension NSScreen {
    static var builtInOrMain: NSScreen {
        screens.first { $0.isBuiltIn } ?? main ?? screens.first!
    }

    var isBuiltIn: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    var notchSize: CGSize {
        guard hasNotch else {
            return CGSize(width: 224, height: 38)
        }

        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        let notchHeight = safeAreaInsets.top + 2

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var notchWindowFrame: CGRect {
        let size = notchSize
        let originX = frame.origin.x + (frame.width - size.width) / 2
        let originY = frame.maxY - size.height
        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}
