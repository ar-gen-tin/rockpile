import SwiftUI

// MARK: - 步骤 1: 欢迎 + 角色选择

extension OnboardingView {
    var roleAndWelcomeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Rockpile").font(.system(size: 26, weight: .bold))
            Text("🐚 \(L10n.s("creature.hermitCrab")) + 🦞 \(L10n.s("creature.crawfish"))")
                .font(.system(size: 13)).foregroundColor(.secondary)

            Spacer().frame(height: 4)

            Text(L10n.s("onboard.roleQuestion")).font(.system(size: 14, weight: .medium))

            VStack(spacing: 8) {
                roleCard(.local,
                         icon: "house.fill",
                         title: L10n.s("onboard.roleLocal"),
                         desc: L10n.s("onboard.roleLocalDesc"),
                         disabled: !setup.isRockpileDetected)
                roleCard(.monitor,
                         icon: "display",
                         title: L10n.s("onboard.roleMonitor"),
                         desc: L10n.s("onboard.roleMonitorDesc"))
                roleCard(.host,
                         icon: "leaf.fill",
                         title: L10n.s("onboard.roleHost"),
                         desc: L10n.s("onboard.roleHostDesc"))
            }
            .padding(.horizontal, 24)

            Spacer()

            navButtons(back: { step = .language }) { step = .configAndO2 }
                .disabled(selectedRole == nil)
        }
        .onAppear {
            // Auto-select local if Rockpile detected and no prior selection
            if selectedRole == nil && setup.isRockpileDetected {
                selectedRole = .local
            }
        }
    }
}
