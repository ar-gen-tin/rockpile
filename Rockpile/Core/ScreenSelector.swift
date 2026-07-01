import AppKit
import Combine

enum ScreenSelectionMode: String, Codable {
    case automatic
    case specificScreen
}

struct ScreenIdentifier: Codable, Equatable, Hashable {
    let displayID: CGDirectDisplayID?
    let localizedName: String

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    init(screen: NSScreen) {
        self.displayID = screen.deviceDescription[Self.screenNumberKey] as? CGDirectDisplayID
        self.localizedName = screen.localizedName
    }

    func matches(_ screen: NSScreen) -> Bool {
        let screenNumber = screen.deviceDescription[Self.screenNumberKey] as? CGDirectDisplayID

        if let savedID = displayID, let screenNumber, savedID == screenNumber {
            return true
        }
        return localizedName == screen.localizedName
    }
}

@MainActor
final class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()

    @Published private(set) var availableScreens: [NSScreen] = []
    @Published private(set) var selectedScreen: NSScreen?
    @Published var selectionMode: ScreenSelectionMode = .automatic

    private let modeKey = "screenSelectionMode"
    private let screenIdentifierKey = "selectedScreenIdentifier"
    private var savedIdentifier: ScreenIdentifier?

    private init() {
        loadPreferences()
        refreshScreens()
    }

    func refreshScreens() {
        availableScreens = NSScreen.screens
        selectedScreen = resolveSelectedScreen()
    }

    func selectScreen(_ screen: NSScreen) {
        selectionMode = .specificScreen
        savedIdentifier = ScreenIdentifier(screen: screen)
        selectedScreen = screen
        savePreferences()
    }

    func selectAutomatic() {
        selectionMode = .automatic
        savedIdentifier = nil
        selectedScreen = resolveSelectedScreen()
        savePreferences()
    }

    private func resolveSelectedScreen() -> NSScreen? {
        switch selectionMode {
        case .automatic:
            return NSScreen.builtInOrMain

        case .specificScreen:
            if let identifier = savedIdentifier,
               let match = availableScreens.first(where: { identifier.matches($0) }) {
                return match
            }
            return NSScreen.builtInOrMain
        }
    }

    private func loadPreferences() {
        if let modeString = UserDefaults.standard.string(forKey: modeKey),
           let mode = ScreenSelectionMode(rawValue: modeString) {
            selectionMode = mode
        }

        if let data = UserDefaults.standard.data(forKey: screenIdentifierKey),
           let identifier = try? JSONDecoder().decode(ScreenIdentifier.self, from: data) {
            savedIdentifier = identifier
        }
    }

    private func savePreferences() {
        UserDefaults.standard.set(selectionMode.rawValue, forKey: modeKey)

        if let identifier = savedIdentifier,
           let data = try? JSONEncoder().encode(identifier) {
            UserDefaults.standard.set(data, forKey: screenIdentifierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: screenIdentifierKey)
        }
    }
}
