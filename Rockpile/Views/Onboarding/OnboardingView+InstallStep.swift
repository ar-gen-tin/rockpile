import SwiftUI

// MARK: - 步骤 3: 安装 + 测试 + 版本更新摘要 + 共用组件

extension OnboardingView {
    var updateSummaryView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)

            // Logo + version
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            Text("Rockpile v\(AppSettings.currentAppVersion)")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 6)

            Spacer().frame(height: 20)

            // What's new
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.s("onboard.thisUpdate"), systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(AppSettings.versionNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 28)

            Spacer().frame(height: 16)

            // Current settings summary
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.s("onboard.currentSettings"), systemImage: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    settingSummaryRow(L10n.s("settings.mode"), roleName(AppSettings.setupRole))
                    settingSummaryRow("🐚 " + L10n.s("settings.localO2"),
                        "\(AppSettings.isLocalClaudeMode ? L10n.s("settings.claudeQuota") : L10n.s("settings.paidUsage")) / \(TokenTracker.formatTokens(AppSettings.localOxygenTankCapacity))")
                    if AppSettings.remoteEnabled {
                        settingSummaryRow("🦞 " + L10n.s("settings.remoteO2"),
                            "\(AppSettings.isRemotePaidMode ? L10n.s("settings.paidUsage") : L10n.s("settings.claudeQuota")) / \(TokenTracker.formatTokens(AppSettings.remoteOxygenTankCapacity))")
                    }
                    if !AppSettings.rockpileHost.isEmpty {
                        settingSummaryRow(L10n.s("settings.remoteHost"), AppSettings.rockpileHost)
                    }
                    if let ip = SetupManager.getLocalIP() {
                        settingSummaryRow(L10n.s("settings.localIP"), ip)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 28)

            Spacer()

            // Auto-complete status
            if autoCompletePhase != .idle {
                autoCompleteStatusView
                    .padding(.horizontal, 28).padding(.bottom, 8)
            }

            // Buttons
            HStack {
                Button(L10n.s("onboard.reconfigure")) {
                    showingUpdateSummary = false
                    step = .language
                }
                .buttonStyle(.bordered)

                Spacer()

                switch autoCompletePhase {
                case .idle:
                    Button(L10n.s("onboard.keepSettings")) {
                        startQuickUpdate()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)

                case .installing, .testing:
                    Button(L10n.s("onboard.processing")) {}
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(true)

                case .done:
                    Button(L10n.s("onboard.start")) {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)

                case .failed:
                    HStack(spacing: 8) {
                        Button(L10n.s("onboard.retry")) { startQuickUpdate() }
                            .buttonStyle(.bordered)
                        Button(L10n.s("onboard.openSettings")) {
                            showingUpdateSummary = false
                            step = .language
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
    }

    var autoCompleteStatusView: some View {
        HStack(spacing: 8) {
            switch autoCompletePhase {
            case .installing:
                ProgressView().controlSize(.small)
                Text(L10n.s("onboard.installing")).font(.system(size: 12)).foregroundColor(.secondary)
            case .testing:
                ProgressView().controlSize(.small)
                Text(L10n.s("onboard.testingConn")).font(.system(size: 12)).foregroundColor(.secondary)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text(L10n.s("onboard.allReady")).font(.system(size: 12, weight: .medium)).foregroundColor(.green)
            case .failed(let err):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(err).font(.system(size: 11)).foregroundColor(.orange).lineLimit(2)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
    }

    func startQuickUpdate() {
        Task { @MainActor in
            // Phase 1: Install
            autoCompletePhase = .installing
            PluginInstaller.installIfNeeded()

            try? await Task.sleep(for: .milliseconds(300))

            // Phase 2: Skip test for monitor/host — only test local mode
            let role = AppSettings.setupRole
            if role == .host || role == .monitor {
                AppSettings.setupCompleted = true
                autoCompletePhase = .done
                try? await Task.sleep(for: .seconds(1))
                onComplete()
                return
            }

            // Local mode: test connection, but complete even if it fails
            autoCompletePhase = .testing
            await setup.testConnection(host: "localhost")

            AppSettings.setupCompleted = true
            switch setup.connectionTestResult {
            case .success:
                autoCompletePhase = .done
                try? await Task.sleep(for: .seconds(1.5))
                onComplete()
            default:
                autoCompletePhase = .done
                try? await Task.sleep(for: .seconds(1))
                onComplete()
            }
        }
    }

    var installAndTestView: some View {
        VStack(spacing: 16) {
            Spacer()

            switch installPhase {
            case .installing:
                ProgressView().scaleEffect(1.5)
                Text(L10n.s("onboard.installing")).font(.system(size: 16, weight: .medium))

            case .installFailed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44)).foregroundColor(.red)
                Text(L10n.s("onboard.installError")).font(.system(size: 20, weight: .bold))
                Text(L10n.s("onboard.checkPermission"))
                    .font(.system(size: 12)).foregroundColor(.secondary)

            case .testing:
                ProgressView().scaleEffect(1.5)
                Text(L10n.s("onboard.testingConn")).font(.system(size: 16, weight: .medium))

            case .testSuccess:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48)).foregroundColor(.green)
                Text(L10n.s("onboard.allReady")).font(.system(size: 22, weight: .bold))

                if selectedRole == .host {
                    Text(L10n.s("onboard.hostReady"))
                        .font(.system(size: 13)).foregroundColor(.secondary)
                } else {
                    Text(L10n.s("onboard.goFind"))
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }

                if selectedRole != .host {
                    VStack(spacing: 8) {
                        infoRow("folder", .blue, L10n.s("onboard.pluginPath"), "~/.rockpile/plugins/rockpile/")
                        if selectedRole == .host, let ip = decodedIP {
                            infoRow("paperplane", .blue, L10n.s("onboard.eventTarget"), "\(ip):18790")
                        }
                    }.padding(.horizontal, 32)
                }

            case .testFailed(let err):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48)).foregroundColor(.orange)
                Text(L10n.s("onboard.connTestFailed"))
                    .font(.system(size: 16, weight: .bold))
                Text(err).font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Text(L10n.s("onboard.skipHint"))
                    .font(.system(size: 11)).foregroundColor(.secondary)

            case .monitorWaiting:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44)).foregroundColor(.blue)
                Text(L10n.s("onboard.waitingTank")).font(.system(size: 20, weight: .bold))
                Text(L10n.s("onboard.waitingTankDesc"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                Text("\(L10n.s("onboard.pairingCode")): \(setup.pairingCode)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }

            Spacer()

            // Bottom buttons
            HStack {
                if installPhase.isTestFailed {
                    Button(L10n.s("onboard.retry")) {
                        Task {
                            installPhase = .testing
                            let h = selectedRole == .local ? "localhost" : setup.localIPAddress
                            await setup.testConnection(host: h)
                            if case .success = setup.connectionTestResult {
                                installPhase = .testSuccess
                            } else if case .failed(let e) = setup.connectionTestResult {
                                installPhase = .testFailed(e)
                            }
                        }
                    }.buttonStyle(.bordered)
                }

                if installPhase == .installFailed {
                    Button(L10n.s("onboard.retryInstall")) {
                        performInstall()
                    }.buttonStyle(.bordered)
                }

                Spacer()

                switch installPhase {
                case .installing, .testing:
                    EmptyView()
                case .testSuccess:
                    Button(L10n.s("onboard.start")) {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                case .monitorWaiting:
                    Button(L10n.s("onboard.done")) {
                        finishSetup()
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                default:
                    Button(L10n.s("onboard.skip")) {
                        finishSetup()
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    func performInstall() {
        guard let role = selectedRole else { return }

        // Save dual O₂ settings (v2.0)
        AppSettings.localOxygenMode = localO2Mode
        AppSettings.localOxygenTankCapacity = localTankCapacity
        AppSettings.remoteOxygenMode = remoteO2Mode
        AppSettings.remoteOxygenTankCapacity = remoteTankCapacity
        AppSettings.remoteEnabled = remoteEnabled

        // Backward compat: also write legacy keys
        AppSettings.oxygenMode = localO2Mode
        AppSettings.oxygenTankCapacity = localTankCapacity

        // Save Usage API settings (v2.1)
        AppSettings.localProvider = localProvider
        AppSettings.remoteProvider = remoteProvider
        if !localAdminKey.isEmpty, let p = AIProvider(rawValue: localProvider) {
            AdminKeyManager.storeKey(for: p, creature: .hermitCrab, key: localAdminKey)
            AppSettings.localUsageAPIEnabled = true
            if p.needsTeamId { AdminKeyManager.storeTeamId(localTeamId, creature: .hermitCrab) }
        }
        if !remoteAdminKey.isEmpty, let p = AIProvider(rawValue: remoteProvider) {
            AdminKeyManager.storeKey(for: p, creature: .crawfish, key: remoteAdminKey)
            AppSettings.remoteUsageAPIEnabled = true
            if p.needsTeamId { AdminKeyManager.storeTeamId(remoteTeamId, creature: .crawfish) }
        }

        step = .installAndTest
        installPhase = .installing

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))

            switch role {
            case .local:
                let ok = setup.installPluginLocal()
                if !ok {
                    installPhase = .installFailed
                    return
                }
                // Test connection
                installPhase = .testing
                await setup.testConnection(host: "localhost")
                finishSetup()
                if case .success = setup.connectionTestResult {
                    installPhase = .testSuccess
                } else if case .failed(let err) = setup.connectionTestResult {
                    installPhase = .testFailed(err)
                } else {
                    installPhase = .testSuccess
                }

            case .monitor:
                guard let serverIP = decodedIP else {
                    pairingError = L10n.s("onboard.badCode")
                    step = .configAndO2
                    return
                }
                installPhase = .testing
                AppSettings.rockpileHost = serverIP
                let registered = await setup.registerWithServer(serverIP: serverIP)
                finishSetup()
                if registered {
                    installPhase = .testSuccess
                } else {
                    installPhase = .testFailed(L10n.s("onboard.cantConnect") + " \(serverIP)")
                }

            case .host:
                finishSetup()
                installPhase = .monitorWaiting
            }
        }
    }

    func finishSetup() {
        guard let role = selectedRole else { return }
        AppSettings.setupRole = SetupRole(rawValue: role.rawValue) ?? .none
        AppSettings.connectionMode = "plugin"
        AppSettings.setupCompleted = true
    }

    // MARK: - Reusable Components

    func roleCard(_ role: Role, icon: String, title: String, desc: String, disabled: Bool = false) -> some View {
        let selected = selectedRole == role
        return Button {
            if !disabled { selectedRole = role }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(selected ? .white : .accentColor)
                    .frame(width: 34, height: 34)
                    .background(selected ? Color.accentColor : Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(desc).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.06) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.gray.opacity(0.2),
                        lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
    }

    func icon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 36))
            .foregroundColor(color)
    }

    func infoRow(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    func navButtons(back: (() -> Void)?, action: @escaping () -> Void) -> some View {
        HStack {
            if let back = back {
                Button(L10n.s("onboard.back")) { back() }.buttonStyle(.bordered)
            }
            Spacer()
            Button(L10n.s("onboard.next")) { action() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }

    func o2ModeButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.12))
            )
    }

    func settingSummaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    func roleName(_ role: SetupRole) -> String {
        AppSettings.roleName(role)
    }
}
