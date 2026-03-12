import SwiftUI

// MARK: - 步骤 2: 配置 + O₂ 设置

extension OnboardingView {

    var configAndO2View: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 8)

                    // Role-specific config
                    switch selectedRole {
                    case .local:   configLocal
                    case .monitor: configMonitor
                    case .host:    configHost
                    case .none:    EmptyView()
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 1)
                        .padding(.horizontal, 32)

                    // O₂ settings
                    o2ConfigSection

                    Spacer().frame(height: 12)
                }
            }

            navButtons(back: { step = .roleAndWelcome }) { performInstall() }
                .disabled(selectedRole == .monitor && decodedIP == nil)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }

    // — Dual O₂ Config Section (v2.0)
    var o2ConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Local O₂ (寄居蟹) ──
            if selectedRole == .local {
                HStack(spacing: 6) {
                    Text("🐚")
                        .font(.system(size: 14))
                    Text(L10n.s("settings.localO2"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Semantic.localAccent)
                }
                .padding(.horizontal, 32)

                o2ModeRow(mode: $localO2Mode)
                    .padding(.horizontal, 32)

                o2CapacityRow(capacity: $localTankCapacity)
                    .padding(.horizontal, 32)

                if localO2Mode == "paid" {
                    usageAPIConfigSection(
                        creature: .hermitCrab,
                        provider: $localProvider,
                        adminKey: $localAdminKey,
                        teamId: $localTeamId,
                        testState: $localAPITest
                    )
                    .padding(.horizontal, 32)
                }
            }

            // ── Remote O₂ (小龙虾) ──
            if selectedRole == .local {
                // Remote toggle
                HStack(spacing: 6) {
                    Toggle(isOn: $remoteEnabled) {
                        HStack(spacing: 6) {
                            Text("🦞")
                                .font(.system(size: 14))
                            Text(L10n.s("settings.remoteO2"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DS.Semantic.remoteAccent)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, 32)

                if remoteEnabled {
                    o2ModeRow(mode: $remoteO2Mode)
                        .padding(.horizontal, 32)

                    o2CapacityRow(capacity: $remoteTankCapacity)
                        .padding(.horizontal, 32)

                    if remoteO2Mode == "paid" {
                        usageAPIConfigSection(
                            creature: .crawfish,
                            provider: $remoteProvider,
                            adminKey: $remoteAdminKey,
                            teamId: $remoteTeamId,
                            testState: $remoteAPITest
                        )
                        .padding(.horizontal, 32)
                    }
                }
            } else {
                // Monitor mode: single O₂ config
                HStack(spacing: 6) {
                    Image(systemName: "bubbles.and.sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                    Text("O₂")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 32)

                o2ModeRow(mode: $remoteO2Mode)
                    .padding(.horizontal, 32)

                o2CapacityRow(capacity: $remoteTankCapacity)
                    .padding(.horizontal, 32)
            }

            Text(L10n.s("onboard.o2Hint"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
    }

    func o2ModeRow(mode: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.s("onboard.meterMode"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                o2ModeButton(L10n.s("settings.claudeQuota"), isActive: mode.wrappedValue == "claude") {
                    mode.wrappedValue = "claude"
                }
                o2ModeButton(L10n.s("settings.paidUsage"), isActive: mode.wrappedValue == "paid") {
                    mode.wrappedValue = "paid"
                }
            }
        }
    }

    func o2CapacityRow(capacity: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.s("settings.bottleCapacity"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach([500_000, 1_000_000, 2_000_000, 5_000_000], id: \.self) { cap in
                    o2ModeButton(TokenTracker.formatTokens(cap),
                                 isActive: capacity.wrappedValue == cap) {
                        capacity.wrappedValue = cap
                    }
                }
            }
        }
    }

    // — Usage API Config (v2.1)
    func usageAPIConfigSection(
        creature: CreatureType,
        provider: Binding<String>,
        adminKey: Binding<String>,
        teamId: Binding<String>,
        testState: Binding<APITestState>
    ) -> some View {
        let providers: [(String, String)] = [
            (AIProvider.claudeAPI.rawValue, "Anthropic API"),
            (AIProvider.openAI.rawValue, "OpenAI"),
            (AIProvider.xAI.rawValue, "xAI"),
        ]
        let selectedProvider = AIProvider(rawValue: provider.wrappedValue)

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.s("onboard.usageAPI"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Provider picker
            HStack(spacing: 6) {
                ForEach(providers, id: \.0) { (value, label) in
                    o2ModeButton(label, isActive: provider.wrappedValue == value) {
                        provider.wrappedValue = value
                        testState.wrappedValue = .idle
                    }
                }
            }

            // Admin Key input
            if let sp = selectedProvider, sp.supportsUsageAPI {
                SecureField(sp.adminKeyDescription, text: adminKey)
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)

                // Team ID for xAI
                if sp.needsTeamId {
                    TextField("Team ID", text: teamId)
                        .font(.system(size: 12))
                        .textFieldStyle(.roundedBorder)
                }

                // Test button + status
                HStack(spacing: 8) {
                    Button {
                        testAPIConnection(creature: creature, provider: sp,
                                          adminKey: adminKey.wrappedValue,
                                          teamId: teamId.wrappedValue,
                                          testState: testState)
                    } label: {
                        Label(L10n.s("onboard.testConn"), systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(adminKey.wrappedValue.isEmpty || testState.wrappedValue == .testing)

                    switch testState.wrappedValue {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView().controlSize(.mini)
                        Text(L10n.s("onboard.verifying")).font(.system(size: 11)).foregroundColor(.secondary)
                    case .success:
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(L10n.s("onboard.valid")).font(.system(size: 11, weight: .medium)).foregroundColor(.green)
                    case .failed(let msg):
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(msg).font(.system(size: 11)).foregroundColor(.red).lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.1), lineWidth: 1))
    }

    func testAPIConnection(
        creature: CreatureType,
        provider: AIProvider,
        adminKey: String,
        teamId: String,
        testState: Binding<APITestState>
    ) {
        testState.wrappedValue = .testing

        // Temporarily store provider + key so queryNow() can find them
        if creature == .hermitCrab {
            AppSettings.localProvider = provider.rawValue
        } else {
            AppSettings.remoteProvider = provider.rawValue
        }
        AdminKeyManager.storeKey(for: provider, creature: creature, key: adminKey)
        if provider.needsTeamId {
            AdminKeyManager.storeTeamId(teamId, creature: creature)
        }

        Task {
            await UsageQueryService.shared.queryNow(for: creature)
            let error = creature == .hermitCrab
                ? UsageQueryService.shared.localError
                : UsageQueryService.shared.remoteError
            if let error {
                testState.wrappedValue = .failed(error)
            } else {
                testState.wrappedValue = .success
            }
        }
    }

    // — Local config
    var configLocal: some View {
        VStack(spacing: 14) {
            icon("house.fill", color: .blue)
            Text(L10n.s("onboard.localMode")).font(.system(size: 20, weight: .bold))
            Text("\(L10n.s("onboard.localCrab"))\n\(L10n.s("onboard.localCrawfish"))")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            VStack(spacing: 8) {
                infoRow("checkmark.circle.fill", .green, L10n.s("onboard.foundClaude"), "~/.claude/")
                infoRow("bolt.fill", .orange, L10n.s("onboard.autoInstall"), "hooks/")
                infoRow("network", .blue, L10n.s("onboard.localComm"), L10n.s("onboard.unixSocket"))
                if remoteEnabled {
                    infoRow("antenna.radiowaves.left.and.right", .cyan, L10n.s("onboard.remoteConn"), L10n.s("onboard.gatewayWS"))
                }
            }.padding(.horizontal, 32)
        }
    }

    // — Monitor config
    var configMonitor: some View {
        VStack(spacing: 14) {
            icon("display", color: .blue)
            Text(L10n.s("onboard.monitorMode")).font(.system(size: 20, weight: .bold))
            Text(L10n.s("onboard.monitorCodeHint"))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            // Pairing code input
            VStack(spacing: 6) {
                TextField(L10n.s("onboard.enterCode"), text: $pairingInput)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: pairingInput) { _, newValue in
                        pairingError = nil
                        pairingInput = newValue
                            .replacingOccurrences(of: "-", with: "")
                            .replacingOccurrences(of: " ", with: "")
                    }

                if let ip = decodedIP {
                    Label("\(L10n.s("onboard.hostSide")): \(ip)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else if let error = pairingError {
                    Label(error, systemImage: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }

            infoRow("antenna.radiowaves.left.and.right", .blue, L10n.s("settings.localIP"), setup.localIPAddress)
                .padding(.horizontal, 32)

            Text(L10n.s("onboard.listeningTCP").replacingOccurrences(of: "{port}", with: "\(SocketServer.tcpPort)"))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // — Host config
    var configHost: some View {
        VStack(spacing: 14) {
            icon("leaf.fill", color: .blue)
            Text(L10n.s("onboard.hostMode")).font(.system(size: 20, weight: .bold))
            Text(L10n.s("onboard.hostCodeHint"))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            if setup.isRockpileDetected {
                infoRow("checkmark.circle.fill", .green, L10n.s("onboard.foundRockpile"), "~/.rockpile/")
                    .padding(.horizontal, 32)
            } else {
                infoRow("exclamationmark.triangle", .orange, L10n.s("onboard.notFoundRockpile"), L10n.s("onboard.needInstall"))
                    .padding(.horizontal, 32)
            }

            // Pairing code display
            HStack(spacing: 3) {
                ForEach(Array(setup.pairingCode.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(width: 28, height: 38)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.vertical, 4)

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(setup.pairingCode, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
            }) {
                Label(showCopied ? L10n.s("onboard.copied") : L10n.s("onboard.copyCode"),
                      systemImage: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            infoRow("network", .blue, L10n.s("settings.localIP"), setup.localIPAddress)
                .padding(.horizontal, 32)
        }
    }

    var decodedIP: String? {
        SetupManager.codeToIP(pairingInput)
    }

}
