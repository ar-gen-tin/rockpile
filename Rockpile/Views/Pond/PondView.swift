import SwiftUI

// MARK: - Underwater Scene (SpongeBob-inspired)

struct PondView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    /// Oxygen level from the effective session's TokenTracker (1.0 = full, 0.0 = depleted)
    var oxygenLevel: Double = 1.0
    /// Token tracker for default (idle) crawfish when no active session
    var tokenTracker: TokenTracker?

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

                // Render sprites — all sessions as crawfish
                ZStack(alignment: .bottom) {
                    Color.clear
                        .allowsHitTesting(false)

                    if sessions.isEmpty {
                        // Default idle crawfish (always visible, centered)
                        UnderwaterSpriteView(
                            state: .sleeping,
                            xPosition: 0.5,
                            yOffset: -38,
                            totalWidth: geometry.size.width,
                            glowOpacity: 0,
                            isDead: tokenTracker?.isDead ?? false,
                            tokenTracker: tokenTracker
                        )
                    } else if sessions.count == 1, let session = sessions.first {
                        UnderwaterSpriteView(
                            state: session.state,
                            xPosition: 0.5,
                            yOffset: -38,
                            totalWidth: geometry.size.width,
                            glowOpacity: glowOpacity(for: session.id),
                            isDead: session.tokenTracker.isDead,
                            tokenTracker: session.tokenTracker
                        )
                    } else {
                        ForEach(depthSorted(Array(sessions))) { session in
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
                }

                // 🌊 Water surface waves at top
                VStack {
                    WaterSurfaceView(width: geometry.size.width, oxygenLevel: oxygenLevel)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
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
