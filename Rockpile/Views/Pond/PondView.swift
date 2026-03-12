import SwiftUI

// MARK: - Underwater Scene (SpongeBob-inspired)

struct PondView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    /// Oxygen level from the effective session's TokenTracker (1.0 = full, 0.0 = depleted)
    var oxygenLevel: Double = 1.0
    /// Token trackers for default (idle) creatures when no active session
    var localTokenTracker: TokenTracker?
    var remoteTokenTracker: TokenTracker?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Deep ocean gradient — darkens and turns murky when oxygen is low
                LinearGradient(
                    colors: waterGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // 🏖️ Sandy ocean floor (SpongeBob-style ground for creature contrast)
                OceanFloorView(width: geometry.size.width, height: geometry.size.height)

                // Seaweed clusters (rendered ON TOP of sand)
                SeaweedCluster(in: geometry.size)
                    .allowsHitTesting(false)

                // Floating bubbles — fewer when oxygen is low
                BubblesView(in: geometry.size, oxygenLevel: oxygenLevel)
                    .allowsHitTesting(false)

                // 🪨 Bottom decorations (stones + clickable shell, sitting on sand)
                DecorationView(width: geometry.size.width, height: geometry.size.height, groundHeight: OceanFloorView.groundHeight)

                // Murky overlay when oxygen is critically low
                if oxygenLevel < 0.3 {
                    Color(red: 0.05, green: 0.10, blue: 0.02)
                        .opacity(murkyOverlayOpacity)
                        .allowsHitTesting(false)
                }

                // Render sprites — always show both creature types
                ZStack(alignment: .bottom) {
                    Color.clear
                        .allowsHitTesting(false)

                    let crawfish = sessions.filter { $0.creatureType == .crawfish }
                    let crabs = sessions.filter { $0.creatureType == .hermitCrab }

                    // 🦞 Crawfish: mid-water level (30% 池塘需要更高位置)
                    if crawfish.isEmpty {
                        // Default idle crawfish (always visible, swims above sand)
                        UnderwaterSpriteView(
                            state: .sleeping,
                            xPosition: 0.75,
                            yOffset: -45,
                            totalWidth: geometry.size.width,
                            glowOpacity: 0,
                            isDead: remoteTokenTracker?.isDead ?? false,
                            tokenTracker: remoteTokenTracker
                        )
                    } else if crawfish.count == 1, let session = crawfish.first {
                        UnderwaterSpriteView(
                            state: session.state,
                            xPosition: crabs.isEmpty ? 0.5 : session.spriteXPosition,
                            yOffset: crabs.isEmpty ? -38 : max(-60, session.spriteYOffset - 20),
                            totalWidth: geometry.size.width,
                            glowOpacity: glowOpacity(for: session.id),
                            isDead: session.tokenTracker.isDead,
                            tokenTracker: session.tokenTracker
                        )
                    } else {
                        ForEach(depthSorted(crawfish)) { session in
                            UnderwaterSpriteView(
                                state: session.state,
                                xPosition: session.spriteXPosition,
                                yOffset: max(-60, session.spriteYOffset - 20),
                                totalWidth: geometry.size.width,
                                glowOpacity: glowOpacity(for: session.id),
                                isDead: session.tokenTracker.isDead,
                                tokenTracker: session.tokenTracker
                            )
                        }
                    }

                    // 🐚 Hermit crabs: 贴地 — 嵌入沙面
                    // sprite=72pt, 帧底部8px透明(≈9pt), groundHeight=30
                    // yOffset=-16 → 视觉底部 25pt 处, 嵌入沙面 ~5pt
                    if crabs.isEmpty {
                        GroundSpriteView(
                            state: .sleeping,
                            xPosition: 0.25,
                            yOffset: -16,
                            totalWidth: geometry.size.width,
                            glowOpacity: 0,
                            isDead: localTokenTracker?.isDead ?? false,
                            tokenTracker: localTokenTracker
                        )
                    } else if crabs.count == 1, let session = crabs.first {
                        GroundSpriteView(
                            state: session.state,
                            xPosition: crawfish.isEmpty ? 0.5 : session.spriteXPosition,
                            yOffset: crawfish.isEmpty ? -14 : max(-26, session.spriteYOffset - 6),
                            totalWidth: geometry.size.width,
                            glowOpacity: glowOpacity(for: session.id),
                            isDead: session.tokenTracker.isDead,
                            tokenTracker: session.tokenTracker
                        )
                    } else {
                        ForEach(crabs) { session in
                            GroundSpriteView(
                                state: session.state,
                                xPosition: session.spriteXPosition,
                                yOffset: max(-26, session.spriteYOffset - 6),
                                totalWidth: geometry.size.width,
                                glowOpacity: glowOpacity(for: session.id),
                                isDead: session.tokenTracker.isDead,
                                tokenTracker: session.tokenTracker
                            )
                        }
                    }
                }

                // ✨ Cross-creature interaction FX (between sprites and surface)
                InteractionFXView(
                    fxTrigger: InteractionCoordinator.shared.fxTrigger,
                    meetingX: InteractionCoordinator.shared.meetingX,
                    totalWidth: geometry.size.width,
                    interactionType: currentInteractionType
                )

                // 🌊 Water surface waves at top
                VStack {
                    WaterSurfaceView(width: geometry.size.width, oxygenLevel: oxygenLevel)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Extract interaction type from coordinator phase
    private var currentInteractionType: InteractionCoordinator.InteractionType? {
        switch InteractionCoordinator.shared.phase {
        case .interacting(let type): return type
        case .approaching(let type): return type
        default: return nil
        }
    }

    // MARK: - Oxygen-Dependent Visuals

    /// Water gradient shifts from clear blue to dark murky green as oxygen drops
    private var waterGradientColors: [Color] {
        if oxygenLevel > 0.6 {
            // Normal: clear blue ocean
            return [
                Color(red: 0.02, green: 0.08, blue: 0.18),
                Color(red: 0.04, green: 0.14, blue: 0.30),
                Color(red: 0.06, green: 0.20, blue: 0.38),
                Color(red: 0.08, green: 0.25, blue: 0.42),
            ]
        } else if oxygenLevel > 0.3 {
            // Warning: slightly darker, greenish tint
            let mix = (0.6 - oxygenLevel) / 0.3 // 0→1 as oxygen drops 0.6→0.3
            return [
                Color(red: 0.02, green: 0.08 + mix * 0.02, blue: 0.18 - mix * 0.04),
                Color(red: 0.04, green: 0.14 + mix * 0.03, blue: 0.28 - mix * 0.06),
                Color(red: 0.05, green: 0.18 + mix * 0.04, blue: 0.32 - mix * 0.08),
                Color(red: 0.06, green: 0.22 + mix * 0.04, blue: 0.35 - mix * 0.10),
            ]
        } else {
            // Critical: dark murky water
            return [
                Color(red: 0.02, green: 0.06, blue: 0.08),
                Color(red: 0.03, green: 0.10, blue: 0.12),
                Color(red: 0.04, green: 0.14, blue: 0.14),
                Color(red: 0.05, green: 0.16, blue: 0.15),
            ]
        }
    }

    /// Murky green overlay opacity (only active below 30%)
    private var murkyOverlayOpacity: Double {
        let severity = (0.3 - oxygenLevel) / 0.3 // 0→1 as oxygen drops 0.3→0.0
        return severity * 0.25
    }

    private func depthSorted(_ sessions: [SessionData]) -> [SessionData] {
        sessions.sorted { $0.spriteYOffset < $1.spriteYOffset }
    }

    private func glowOpacity(for id: String) -> Double {
        if id == selectedSessionId { return 0.6 }
        return 0.15
    }
}
