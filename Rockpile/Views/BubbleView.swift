import SwiftUI

/// 像素风气泡对话 — 参考 Star-Office-UI 的 BUBBLE_TEXTS + 打字机效果
///
/// 在龙虾精灵上方显示，按当前状态随机选择台词，逐字显示后淡出。

// MARK: - Bubble Texts

@MainActor
enum BubbleTexts {
    static func texts(for task: ClawTask, oxygenStress: Double = 0) -> [String] {
        // stress > 0.7 → 仅低氧台词
        if oxygenStress > 0.7 {
            return L10n.a("bubble.lowO2")
        }
        // stress > 0.4 → 混合正常台词 + 警告台词
        if oxygenStress > 0.4 {
            let normal = taskTexts(for: task)
            let warning = L10n.a("bubble.warningO2")
            return normal + warning
        }
        return taskTexts(for: task)
    }

    private static func taskTexts(for task: ClawTask) -> [String] {
        switch task {
        case .idle:       return L10n.a("bubble.idle")
        case .thinking:   return L10n.a("bubble.thinking")
        case .working:    return L10n.a("bubble.working")
        case .waiting:    return L10n.a("bubble.waiting")
        case .error:      return L10n.a("bubble.error")
        case .sleeping:   return L10n.a("bubble.sleeping")
        case .compacting: return L10n.a("bubble.compacting")
        }
    }

    static var dead: [String] { L10n.a("bubble.dead") }
}

// MARK: - Bubble View

struct PixelBubbleView: View {
    let task: ClawTask
    let isDead: Bool
    let spriteSize: CGFloat
    var oxygenStress: Double = 0

    @State private var displayedText = ""
    @State private var opacity: Double = 0
    @State private var bubbleId = UUID()
    @State private var animationTask: Task<Void, Never>?

    /// Interval between bubble appearances
    private let interval: TimeInterval = 10.0
    /// How long the bubble stays fully visible
    private let stayDuration: TimeInterval = 3.5
    /// Typewriter speed: seconds per character
    private let charDelay: TimeInterval = 0.06

    var body: some View {
        ZStack {
            if !displayedText.isEmpty {
                bubbleShape
                    .opacity(opacity)
                    .id(bubbleId)
            }
        }
        .frame(width: spriteSize * 2, height: 28)
        .offset(y: -spriteSize * 0.45)
        .onAppear { startBubbleLoop() }
        .onDisappear { animationTask?.cancel() }
        .onChange(of: task) { _, _ in
            showNewBubble()
        }
        .onChange(of: isDead) { _, dead in
            if dead { showDeadBubble() }
        }
    }

    @ViewBuilder
    private var bubbleShape: some View {
        HStack(spacing: 0) {
            Text(displayedText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Task-Based Scheduling

    private func startBubbleLoop() {
        animationTask?.cancel()
        animationTask = Task {
            // Initial random delay before first bubble
            let delay = Double.random(in: 5...interval)
            try? await Task.sleep(for: .seconds(delay))

            while !Task.isCancelled {
                let texts = isDead ? BubbleTexts.dead : BubbleTexts.texts(for: task, oxygenStress: oxygenStress)
                guard let text = texts.randomElement() else { break }

                await showBubble(text: text)
                guard !Task.isCancelled else { return }

                // Wait before next bubble
                let nextDelay = Double.random(in: 5...interval)
                try? await Task.sleep(for: .seconds(nextDelay))
            }
        }
    }

    private func showNewBubble() {
        let texts = isDead ? BubbleTexts.dead : BubbleTexts.texts(for: task, oxygenStress: oxygenStress)
        guard let text = texts.randomElement() else { return }

        animationTask?.cancel()
        animationTask = Task {
            await showBubble(text: text)
            guard !Task.isCancelled else { return }

            // Resume the loop after this immediate bubble
            let nextDelay = Double.random(in: 5...interval)
            try? await Task.sleep(for: .seconds(nextDelay))

            while !Task.isCancelled {
                let texts = isDead ? BubbleTexts.dead : BubbleTexts.texts(for: task, oxygenStress: oxygenStress)
                guard let text = texts.randomElement() else { break }

                await showBubble(text: text)
                guard !Task.isCancelled else { return }

                let delay = Double.random(in: 5...interval)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func showDeadBubble() {
        guard let text = BubbleTexts.dead.randomElement() else { return }

        animationTask?.cancel()
        animationTask = Task {
            await showBubble(text: text)
        }
    }

    /// Typewrite a single bubble text, stay visible, then fade out
    private func showBubble(text: String) async {
        displayedText = ""
        opacity = 1.0
        bubbleId = UUID()

        // Typewriter effect — O(1) per character via Array
        let chars = Array(text)
        for i in 0..<chars.count {
            guard !Task.isCancelled else { return }
            displayedText = String(chars[0...i])
            try? await Task.sleep(for: .seconds(charDelay))
        }

        guard !Task.isCancelled else { return }

        // Stay visible
        try? await Task.sleep(for: .seconds(stayDuration))
        guard !Task.isCancelled else { return }

        // Fade out
        withAnimation(.easeOut(duration: 0.5)) {
            opacity = 0
        }
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled else { return }
        displayedText = ""
    }
}
