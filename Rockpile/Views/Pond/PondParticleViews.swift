import SwiftUI

// MARK: - Bubbles

struct BubblesView: View {
    let size: CGSize
    let oxygenLevel: Double

    init(in size: CGSize, oxygenLevel: Double = 1.0) {
        self.size = size
        self.oxygenLevel = oxygenLevel
    }

    // Fixed bubble positions (seeded, not random each frame)
    private let allBubbles: [(x: CGFloat, speed: Double, bubbleSize: CGFloat, phase: Double)] = [
        (0.15, 12, 3, 0.0),
        (0.30, 16, 2, 2.1),
        (0.45, 10, 4, 4.5),
        (0.60, 14, 2.5, 1.3),
        (0.75, 18, 3, 3.7),
        (0.85, 11, 2, 5.2),
        (0.20, 15, 3.5, 6.0),
        (0.55, 13, 2, 0.8),
    ]

    /// Number of visible bubbles based on oxygen level
    private var visibleBubbleCount: Int {
        if oxygenLevel <= 0 { return 0 }          // Dead: no bubbles at all
        if oxygenLevel < 0.1 { return 1 }          // Near-death: 1 slow bubble
        return max(1, Int(Double(allBubbles.count) * oxygenLevel))
    }

    /// Bubble speed multiplier — slower when oxygen is low
    private var speedMultiplier: Double {
        if oxygenLevel <= 0 { return 0 }
        return max(0.3, oxygenLevel)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                guard !reduceMotion else { return } // Hide decorative bubbles
                let bubbles = Array(allBubbles.prefix(visibleBubbleCount))
                for bubble in bubbles {
                    let adjustedSpeed = bubble.speed / speedMultiplier
                    let cycleTime = adjustedSpeed
                    let progress = ((t + bubble.phase).truncatingRemainder(dividingBy: cycleTime)) / cycleTime
                    let x = canvasSize.width * bubble.x + sin(t * 0.5 + bubble.phase) * 4
                    let y = canvasSize.height * (1.0 - progress)

                    // Bubbles become more transparent when oxygen is low
                    let alphaScale = max(0.4, oxygenLevel)

                    let rect = CGRect(
                        x: x - bubble.bubbleSize,
                        y: y - bubble.bubbleSize,
                        width: bubble.bubbleSize * 2,
                        height: bubble.bubbleSize * 2
                    )

                    // Bubble outline
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: 0.5, green: 0.75, blue: 0.95).opacity(0.35 * alphaScale)),
                        lineWidth: 0.8
                    )
                    // Bubble highlight
                    let highlightRect = CGRect(
                        x: x - bubble.bubbleSize * 0.3,
                        y: y - bubble.bubbleSize * 0.5,
                        width: bubble.bubbleSize * 0.6,
                        height: bubble.bubbleSize * 0.4
                    )
                    context.fill(
                        Path(ellipseIn: highlightRect),
                        with: .color(Color.white.opacity(0.15 * alphaScale))
                    )
                }
            }
        }
    }
}

// MARK: - Breath Bubbles (linked to sprite)

/// 龙虾嘴部冒出的小气泡 — 频率随状态变化
struct BreathBubblesView: View {
    let isDead: Bool
    let task: ClawTask
    let spriteSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bubble cycle time based on task activity
    private var cycleBase: Double {
        if isDead { return 100 } // Effectively invisible
        switch task {
        case .working:    return 2.0
        case .thinking:   return 2.8
        case .idle:       return 4.0
        case .compacting: return 2.5
        case .sleeping:   return 6.0
        case .waiting:    return 4.5
        case .error:      return 3.5
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: isDead || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                guard !isDead, !reduceMotion else { return }
                // Mouth area: slightly right and above center of sprite
                let mouthX = size.width / 2 + 6
                let mouthY = size.height / 2 - 4

                // 3 tiny bubbles rising from mouth
                for i in 0..<3 {
                    let phase = Double(i) * 1.3
                    let cycle = cycleBase + Double(i) * 0.6
                    let progress = ((t + phase).truncatingRemainder(dividingBy: cycle)) / cycle

                    let x = mouthX + CGFloat(sin(t * 0.7 + phase) * 2.5)
                    let y = mouthY - CGFloat(progress) * spriteSize * 0.4

                    // Deterministic size based on index
                    let bSize: CGFloat = 1.5 + CGFloat(i) * 0.4
                    let alpha = (1.0 - progress) * 0.45

                    let rect = CGRect(
                        x: x - bSize / 2, y: y - bSize / 2,
                        width: bSize, height: bSize
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: 0.5, green: 0.78, blue: 0.95).opacity(alpha)),
                        lineWidth: 0.5
                    )
                }
            }
        }
        .frame(width: spriteSize, height: spriteSize)
        .allowsHitTesting(false)
    }
}

// MARK: - Heart Particles (double-tap reaction)

/// 双击龙虾时的心形粒子效果
struct HeartParticlesView: View {
    let triggerCounter: Int
    let size: CGFloat

    @State private var hearts: [HeartParticle] = []
    @State private var startTime: Double = 0

    private struct HeartParticle: Identifiable {
        let id = UUID()
        let startX: CGFloat
        let xDrift: CGFloat
        let speed: Double
        let scale: CGFloat
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: hearts.isEmpty)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate - startTime
            ZStack {
                ForEach(hearts) { heart in
                    let progress = min(1.0, elapsed * heart.speed)
                    Text("\u{2764}\u{FE0F}")
                        .font(.system(size: 8 * heart.scale))
                        .offset(
                            x: heart.startX + sin(elapsed * 2 + Double(heart.xDrift)) * 5,
                            y: -CGFloat(progress) * size * 0.5
                        )
                        .opacity(max(0, 1.0 - progress))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onChange(of: triggerCounter) { _, _ in
            spawnHearts()
        }
    }

    private func spawnHearts() {
        let count = Int.random(in: 3...5)
        var newHearts: [HeartParticle] = []
        for _ in 0..<count {
            newHearts.append(HeartParticle(
                startX: CGFloat.random(in: -15...15),
                xDrift: CGFloat.random(in: -3...3),
                speed: Double.random(in: 0.5...0.9),
                scale: CGFloat.random(in: 0.8...1.3)
            ))
        }
        hearts = newHearts
        startTime = Date.timeIntervalSinceReferenceDate

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            hearts = []
        }
    }
}
