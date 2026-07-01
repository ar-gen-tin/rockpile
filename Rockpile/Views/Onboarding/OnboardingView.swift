import SwiftUI

/// Onboarding 主入口 — 步骤导航 + 状态管理
///
/// 各步骤视图通过 extension 分散在同目录下的独立文件中:
/// - OnboardingView+LanguageStep.swift (步骤 0)
/// - OnboardingView+RoleStep.swift (步骤 1)
/// - OnboardingView+ConfigStep.swift (步骤 2)
/// - OnboardingView+InstallStep.swift (步骤 3 + actions + components + update summary)
struct OnboardingView: View {
    // Note: @State uses internal access (not private) so that extensions
    // in separate files can access them. @State prevents external mutation.
    @State var setup = SetupManager()
    @State var step: Step = .language
    @State var selectedRole: Role?
    @State var pairingInput: String = ""
    @State var pairingError: String?
    @State var showCopied = false

    // Dual O₂ settings (v2.0)
    @State var localO2Mode: String = AppSettings.localOxygenMode
    @State var localTankCapacity: Int = AppSettings.localOxygenTankCapacity
    @State var remoteO2Mode: String = AppSettings.remoteOxygenMode
    @State var remoteTankCapacity: Int = AppSettings.remoteOxygenTankCapacity
    @State var remoteEnabled: Bool = AppSettings.remoteEnabled

    // Usage API settings (v2.1)
    @State var localProvider: String = AppSettings.localProvider
    @State var remoteProvider: String = AppSettings.remoteProvider
    @State var localAdminKey: String = ""
    @State var remoteAdminKey: String = ""
    @State var localTeamId: String = AdminKeyManager.readTeamId(creature: .hermitCrab) ?? ""
    @State var remoteTeamId: String = AdminKeyManager.readTeamId(creature: .crawfish) ?? ""
    @State var localAPITest: APITestState = .idle
    @State var remoteAPITest: APITestState = .idle

    // Language refresh
    @State var languageRefresh = 0
    @State var installPhase: InstallPhase = .installing

    enum APITestState: Equatable {
        case idle, testing, success, failed(String)
    }

    // Update flow
    @State var showingUpdateSummary: Bool
    @State var autoCompletePhase: AutoCompletePhase = .idle

    var onComplete: () -> Void

    enum Step: Equatable { case language, roleAndWelcome, configAndO2, installAndTest }

    enum Role: String, CaseIterable {
        case local   = "local"
        case monitor = "monitor"
        case host    = "host"
    }

    enum AutoCompletePhase: Equatable {
        case idle, installing, testing, done, failed(String)
    }

    enum InstallPhase: Equatable {
        case installing
        case installFailed
        case testing
        case testSuccess
        case testFailed(String)
        case monitorWaiting

        var isTestFailed: Bool {
            if case .testFailed = self { return true }
            return false
        }
    }

    init(isUpdate: Bool = false, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        self._showingUpdateSummary = State(initialValue: isUpdate)

        // Pre-fill from saved settings
        let savedRole = AppSettings.setupRole.rawValue
        if let role = Role(rawValue: savedRole) {
            self._selectedRole = State(initialValue: role)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingUpdateSummary {
                updateSummaryView
            } else {
                progressBar.padding(.top, 16).padding(.horizontal, 24)

                Group {
                    switch step {
                    case .language:       languageSelectionView
                    case .roleAndWelcome: roleAndWelcomeView
                    case .configAndO2:    configAndO2View
                    case .installAndTest: installAndTestView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .frame(width: 460, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { setup.detectRockpile() }
        .id(languageRefresh)
    }

    // MARK: - Progress (4 Steps)

    private var progressBar: some View {
        let steps: [Step] = [.language, .roleAndWelcome, .configAndO2, .installAndTest]
        let idx = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= idx ? Color.accentColor : Color.gray.opacity(0.25))
                    .frame(height: 3)
            }
        }
    }
}
