import SwiftUI

// MARK: - Underwater Scene (极简深蓝 — Notchi-inspired)

struct PondView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    /// Oxygen level from the effective session's TokenTracker (1.0 = full, 0.0 = depleted)
    var oxygenLevel: Double = 1.0
    /// Token trackers for default (idle) creatures when no active session
    var localTokenTracker: TokenTracker?
    var remoteTokenTracker: TokenTracker?
    /// Callback when a creature sprite is tapped
    var onSelectSession: ((String) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Deep ocean gradient — minimal dark blue
                LinearGradient(
                    colors: waterGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Sparse bubbles only
                BubblesView(in: geometry.size, oxygenLevel: oxygenLevel)
                    .allowsHitTesting(false)

                // Murky overlay when oxygen is critically low
                if oxygenLevel < 0.3 {
                    Color(red: 0.05, green: 0.10, blue: 0.02)
                        .opacity(murkyOverlayOpacity)
                        .allowsHitTesting(false)
                }

                // Render sprites — scale to fit pond, clamp inside
                let pondW = geometry.size.width
                let pondH = geometry.size.height
                // Scale sprites down if pond is too small
                let spriteScale = min(1.0, pondH / 150.0)

                let crawfish = sessions.filter { $0.creatureType == .crawfish }
                let crabs = sessions.filter { $0.creatureType == .hermitCrab }

                // 🦞 Crawfish: upper 35% of pond
                Group {
                    if crawfish.isEmpty {
                        UnderwaterSpriteView(
                            state: .sleeping,
                            xPosition: 0.70,
                            yOffset: 0,
                            totalWidth: pondW,
                            glowOpacity: 0,
                            isDead: remoteTokenTracker?.isDead ?? false,
                            tokenTracker: remoteTokenTracker
                        )
                    } else if crawfish.count == 1, let session = crawfish.first {
                        UnderwaterSpriteView(
                            state: session.state,
                            xPosition: crabs.isEmpty ? 0.5 : 0.65,
                            yOffset: 0,
                            totalWidth: pondW,
                            glowOpacity: glowOpacity(for: session.id),
                            isDead: session.tokenTracker.isDead,
                            tokenTracker: session.tokenTracker
                        )
                        .onTapGesture { onSelectSession?(session.id) }
                    } else {
                        ForEach(depthSorted(crawfish)) { session in
                            UnderwaterSpriteView(
                                state: session.state,
                                xPosition: session.spriteXPosition,
                                yOffset: 0,
                                totalWidth: pondW,
                                glowOpacity: glowOpacity(for: session.id),
                                isDead: session.tokenTracker.isDead,
                                tokenTracker: session.tokenTracker
                            )
                            .onTapGesture { onSelectSession?(session.id) }
                        }
                    }
                }
                .scaleEffect(spriteScale)
                .position(x: pondW * 0.65, y: pondH * 0.30)

                // 🐚 Hermit crabs: lower 65% of pond
                Group {
                    if crabs.isEmpty {
                        GroundSpriteView(
                            state: .sleeping,
                            xPosition: 0.30,
                            yOffset: 0,
                            totalWidth: pondW,
                            glowOpacity: 0,
                            isDead: localTokenTracker?.isDead ?? false,
                            tokenTracker: localTokenTracker
                        )
                    } else if crabs.count == 1, let session = crabs.first {
                        GroundSpriteView(
                            state: session.state,
                            xPosition: crawfish.isEmpty ? 0.5 : 0.35,
                            yOffset: 0,
                            totalWidth: pondW,
                            glowOpacity: glowOpacity(for: session.id),
                            isDead: session.tokenTracker.isDead,
                            tokenTracker: session.tokenTracker
                        )
                        .onTapGesture { onSelectSession?(session.id) }
                    } else {
                        ForEach(crabs) { session in
                            GroundSpriteView(
                                state: session.state,
                                xPosition: session.spriteXPosition,
                                yOffset: 0,
                                totalWidth: pondW,
                                glowOpacity: glowOpacity(for: session.id),
                                isDead: session.tokenTracker.isDead,
                                tokenTracker: session.tokenTracker
                            )
                            .onTapGesture { onSelectSession?(session.id) }
                        }
                    }
                }
                .scaleEffect(spriteScale)
                .position(x: pondW * 0.35, y: pondH * 0.65)

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
            .drawingGroup()  // Metal compositing for smoother animations
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

    /// Water gradient — minimal deep blue, darkens when oxygen drops
    private var waterGradientColors: [Color] {
        if oxygenLevel > 0.6 {
            return [
                Color(red: 0.01, green: 0.04, blue: 0.08),
                Color(red: 0.02, green: 0.06, blue: 0.15),
                Color(red: 0.03, green: 0.09, blue: 0.22),
            ]
        } else if oxygenLevel > 0.3 {
            let mix = (0.6 - oxygenLevel) / 0.3
            return [
                Color(red: 0.01, green: 0.04 + mix * 0.01, blue: 0.08 - mix * 0.02),
                Color(red: 0.02, green: 0.06 + mix * 0.02, blue: 0.14 - mix * 0.04),
                Color(red: 0.03, green: 0.08 + mix * 0.02, blue: 0.18 - mix * 0.06),
            ]
        } else {
            return [
                Color(red: 0.01, green: 0.03, blue: 0.04),
                Color(red: 0.02, green: 0.05, blue: 0.06),
                Color(red: 0.03, green: 0.07, blue: 0.08),
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
