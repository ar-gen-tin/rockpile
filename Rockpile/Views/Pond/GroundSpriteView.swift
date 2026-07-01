import SwiftUI

// MARK: - Ground Sprite (Hermit Crab Interactive)

/// 寄居蟹互动精灵 — 底部爬行，壳缩/弹反应
struct GroundSpriteView: View {
    let state: ClawState
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat
    let glowOpacity: Double
    var isDead: Bool = false
    var tokenTracker: TokenTracker?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spriteSize: CGFloat = 72
    private static let usableWidthFraction: CGFloat = 0.8
    private static let leftMarginFraction: CGFloat = 0.1

    /// 使用传入的 yOffset（不再硬编码贴地偏移，极简水塘无沙地）
    private var effectiveYOffset: CGFloat {
        yOffset
    }

    // ── Crawling (arc path, slower) ──
    @State private var crawlOffset: CGFloat = 0
    @State private var crawlVertical: CGFloat = 0  // 弧形路径的垂直分量
    @State private var facingLeft: Bool = false
    @State private var canCrawl: Bool = false

    // ── Entry animation ──
    @State private var entryScale: CGFloat = 0.3

    // ── State transition ──
    @State private var transitionScale: CGFloat = 1.0
    @State private var transitionCounter: Int = 0

    // ── Interaction: shell retract (tap) ──
    @State private var shellRetracted: Bool = false
    @State private var tapCooldown: Bool = false
    @State private var reactionText: String? = nil
    @State private var reactionOpacity: Double = 0

    // ── Interaction: triple-tap punishment ──
    @State private var recentTapTimes: [Date] = []
    @State private var isAngry: Bool = false

    // ── Interaction: drag (自由拖放，松手保持位置) ──
    @State private var dragOffset: CGSize = .zero
    @State private var dragBase: CGSize = .zero   // 累积的拖拽位置
    @State private var isDragging: Bool = false

    // ── Interaction: double-tap hearts ──
    @State private var heartCounter: Int = 0

    // ── Interaction: long-press info card ──
    @State private var showInfoCard: Bool = false
    @State private var infoCardDismissId: UUID = UUID()

    // ── Interaction: feeding ──
    @State private var feedCounter: Int = 0
    @State private var feedReactionScale: CGFloat = 1.0

    // ── Cross-creature interaction (互动) ──
    @State private var interactionOffset: CGSize = .zero

    // ── 点击唤醒 ──
    @State private var manuallyAwake: Bool = false

    private var xOffset: CGFloat {
        let usableWidth = totalWidth * Self.usableWidthFraction
        let leftMargin = totalWidth * Self.leftMarginFraction
        return leftMargin + (xPosition * usableWidth) - (totalWidth / 2)
    }

    private var stateColor: Color { state.task.statusColor }

    var body: some View {
        ZStack {
            // Main sprite container
            ZStack {
                // 🐚 Core sprite — hermit crab
                HermitCrabSpriteView(
                    state: state,
                    isSelected: glowOpacity > 0.3,
                    size: Self.spriteSize,
                    isDead: isDead
                )

                // ✨ Transition star particles
                TransitionFXView(
                    triggerCounter: transitionCounter,
                    stateColor: stateColor,
                    size: Self.spriteSize
                )
            }
            .scaleEffect(entryScale * transitionScale * feedReactionScale)
            // Shell retract: shrink briefly on tap
            .scaleEffect(shellRetracted ? 0.8 : 1.0)
            .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            .frame(width: Self.spriteSize, height: Self.spriteSize)
            .contentShape(Rectangle())
            // ── Gestures: drag (horizontal only for crab) ──
            // highPriorityGesture 确保拖拽优先于 tap/longPress
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            canCrawl = false
                            InteractionCoordinator.shared.cancelInteraction()
                        }
                        // 自由 2D 拖放 — 不再限制水平
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        // 松手保持位置: 累积到 dragBase
                        dragBase = CGSize(
                            width: dragBase.width + value.translation.width,
                            height: dragBase.height + value.translation.height
                        )
                        dragOffset = .zero
                        // 轻微弹性落定
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            // 微调: 松手后轻微下沉模拟重力
                            dragBase.height += 2
                        }
                        if (state.task.canWalk || manuallyAwake) && !isDead && !reduceMotion {
                            canCrawl = true
                            scheduleCrawl()
                        }
                        updateInteractionEligibility()
                    }
            )
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
            .onTapGesture(count: 1) {
                handleSingleTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                handleLongPress()
            }
            .contextMenu {
                if let tracker = tokenTracker {
                    Button {
                        handleFeed(tracker: tracker)
                    } label: {
                        if tracker.isOverfed {
                            Label(L10n.s("feed.overfed"), systemImage: "face.dashed")
                        } else if tracker.canFeed {
                            Label(L10n.s("feed.feed"), systemImage: "fork.knife")
                        } else {
                            let remaining = Int(tracker.feedCooldownRemaining)
                            Label("\(L10n.s("feed.cooldown")) \(remaining)s", systemImage: "clock")
                        }
                    }
                    .disabled(!tracker.canFeed)
                } else {
                    Button {} label: {
                        Label(L10n.s("sprite.noSession"), systemImage: "zzz")
                    }
                    .disabled(true)
                }
            }
            .accessibilityLabel("\(L10n.s("sprite.accessCrab")), \(state.displayName)")
            .accessibilityHint(L10n.s("sprite.accessHint"))

            // ❤️ Heart particles (double-tap)
            HeartParticlesView(triggerCounter: heartCounter, size: Self.spriteSize)

            // 🫧 Bubble dialog above sprite
            PixelBubbleView(task: state.task, isDead: isDead, spriteSize: Self.spriteSize,
                            oxygenStress: tokenTracker?.oxygenStress ?? 0)
                .allowsHitTesting(false)

            // 💬 Reaction text (tap feedback)
            if let reaction = reactionText {
                Text(reaction)
                    .font(DS.Font.monoBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Semantic.localAccent.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .offset(y: -Self.spriteSize * 0.65)
                    .opacity(reactionOpacity)
                    .allowsHitTesting(false)
            }

            // 📋 Info card (long-press)
            SpriteInfoCardView(
                state: state,
                oxygenLevel: tokenTracker?.oxygenLevel ?? 1.0,
                sessionTokens: tokenTracker?.sessionTotalTokens ?? 0,
                isVisible: showInfoCard,
                burnRateText: (tokenTracker?.burnRate ?? 0) > 0 ? tokenTracker?.burnRateText : nil,
                etaText: tokenTracker?.etaText
            )
            .offset(x: Self.spriteSize * 0.45, y: -Self.spriteSize * 0.3)
            .id(infoCardDismissId)

            // 🍤 Food particles (feeding)
            FoodParticleView(
                triggerCounter: feedCounter,
                targetY: Self.spriteSize * 0.4,
                size: Self.spriteSize * 2
            )
            .offset(y: -Self.spriteSize * 0.3)
        }
        .shadow(color: DS.Semantic.localAccent.opacity(glowOpacity * 0.4), radius: 5)
        .offset(x: xOffset + crawlOffset + interactionOffset.width + dragBase.width + dragOffset.width,
                y: effectiveYOffset + crawlVertical + interactionOffset.height + dragBase.height + dragOffset.height)
        .onAppear {
            if reduceMotion {
                entryScale = 1.0
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    entryScale = 1.0
                }
            }
            canCrawl = state.task.canWalk && !isDead && !reduceMotion
            if canCrawl { scheduleCrawl() }
            // 互动: 注册可互动状态
            updateInteractionEligibility()
        }
        .onChange(of: state.task) { _, newTask in
            if !reduceMotion {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                    transitionScale = 1.15
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        transitionScale = 1.0
                    }
                }
                transitionCounter += 1
            }
            canCrawl = newTask.canWalk && !isDead && !reduceMotion
            if canCrawl { scheduleCrawl() }
            updateInteractionEligibility()
        }
        .onChange(of: isDead) { _, dead in
            canCrawl = state.task.canWalk && !dead && !reduceMotion
            updateInteractionEligibility()
        }
        // ── Cross-creature interaction phase observer ──
        .onChange(of: InteractionCoordinator.shared.phase) { _, newPhase in
            handleInteractionPhase(newPhase)
        }
    }

    // MARK: - Crawling Logic (slower, ground-only)

    private func scheduleCrawl() {
        let delay = Double.random(in: 12.0...20.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard canCrawl else { return }
            performCrawl()
        }
    }

    private func performCrawl() {
        // stress 高时: 幅度缩小 (疲惫)，速度减慢
        let stress = tokenTracker?.oxygenStress ?? 0
        let maxOffset: CGFloat = 15 * CGFloat(max(0.3, 1.0 - stress))
        let target = CGFloat.random(in: -maxOffset...maxOffset)
        facingLeft = target < crawlOffset

        let duration = Double.random(in: 1.5...3.0) * (1.0 + stress * 0.5)
        let halfDuration = duration / 2

        // 弧形路径: 先上升再下降，模拟自然爬行
        let arcHeight = CGFloat.random(in: (-4)...(-1)) // 负值 = 上移
        withAnimation(.easeIn(duration: halfDuration)) {
            crawlOffset = (crawlOffset + target) / 2
            crawlVertical = arcHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + halfDuration) {
            withAnimation(.easeOut(duration: halfDuration)) {
                crawlOffset = target
                crawlVertical = 0 // 落回地面
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            guard canCrawl else { return }
            scheduleCrawl()
        }
    }

    // MARK: - Interaction Handlers

    private func handleSingleTap() {
        guard !tapCooldown, !isDead else { return }
        tapCooldown = true

        // Triple-tap punishment detection
        let now = Date()
        recentTapTimes.append(now)
        recentTapTimes.removeAll { now.timeIntervalSince($0) > 2.0 }

        if recentTapTimes.count >= 3 {
            handlePunishment()
            recentTapTimes.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { tapCooldown = false }
            return
        }

        // 点击唤醒: 睡眠状态下点击 → 立即开始爬行 60 秒
        if !canCrawl && !isDead && !reduceMotion {
            manuallyAwake = true
            canCrawl = true
            performCrawl()   // ← 立即移动，不等 12-20 秒
            // 60 秒后自动入睡
            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                guard manuallyAwake else { return }
                manuallyAwake = false
                if !state.task.canWalk {
                    canCrawl = false
                }
            }
        }

        // Shell retract: 寄居蟹性格内向，被戳 → 缩壳 → 慢慢探出
        withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) {
            shellRetracted = true
        }
        // Longer retract for shy personality (0.5s vs crawfish's instant)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                shellRetracted = false
            }
        }

        // State-aware reaction (crab is more laconic)
        showReaction(CreatureReactions.tapReaction(creature: .hermitCrab, task: state.task, isDead: isDead))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { tapCooldown = false }
    }

    private func handleDoubleTap() {
        guard !isDead else { return }
        heartCounter += 1

        // Shy love reaction — smaller bounce (crab is reserved)
        showReaction(CreatureReactions.loveReaction(creature: .hermitCrab, task: state.task, isDead: isDead), duration: 1.5)

        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            transitionScale = 1.08  // Smaller bounce than crawfish (1.15)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                transitionScale = 1.0
            }
        }
    }

    private func handleLongPress() {
        guard !isDead else { return }
        showInfoCard = true
        infoCardDismissId = UUID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { showInfoCard = false }
    }

    private func handleFeed(tracker: TokenTracker) {
        let wasOverfed = tracker.isOverfed
        guard tracker.feed() else {
            if wasOverfed || tracker.isOverfed {
                showReaction(CreatureReactions.feedReaction(creature: .hermitCrab, isOverfed: true))
                // Crab: retreats into shell when overfed
                withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                    shellRetracted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                        shellRetracted = false
                    }
                }
            }
            return
        }

        feedCounter += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Smaller reaction (shy)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                feedReactionScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    feedReactionScale = 1.0
                }
            }

            let isNowOverfed = tracker.isOverfed
            showReaction(CreatureReactions.feedReaction(creature: .hermitCrab, isOverfed: isNowOverfed), duration: 1.5)
        }
    }

    /// Triple-tap punishment: deep shell retract + angry reaction + -2% O₂
    private func handlePunishment() {
        isAngry = true
        showReaction(CreatureReactions.punishReaction(creature: .hermitCrab), duration: 2.0)

        // Crab punishment: deep shell retract (shrinks to 0.6 instead of 0.8)
        withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) {
            shellRetracted = true
            transitionScale = 0.6  // Deep retract — scared
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                shellRetracted = false
                transitionScale = 1.0
            }
        }

        // Penalty: reduce feed bonus (effectively -2% O₂)
        if let tracker = tokenTracker {
            let penalty = Int(Double(max(1, AppSettings.localOxygenTankCapacity)) * 0.02)
            tracker.feedBonusTokens = max(0, tracker.feedBonusTokens - penalty)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { isAngry = false }
    }

    // MARK: - Reaction Display Helper

    private func showReaction(_ text: String?, duration: Double = 1.2) {
        guard let text else { return }
        reactionText = text
        reactionOpacity = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: 0.3)) { reactionOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { reactionText = nil }
        }
    }

    // MARK: - Cross-Creature Interaction (寄居蟹侧)

    private func updateInteractionEligibility() {
        let eligible = (state.task == .idle || state.task == .sleeping) && !isDead && !isDragging && !reduceMotion
        InteractionCoordinator.shared.crabCanInteract = eligible
    }

    private func handleInteractionPhase(_ phase: InteractionCoordinator.Phase) {
        let coordinator = InteractionCoordinator.shared

        switch phase {
        case .approaching(let type):
            // 暂停爬行，向会合点移动 (蟹只做水平移动)
            canCrawl = false
            let meetX = coordinator.meetingX
            let targetX = (meetX - xPosition) * totalWidth * Self.usableWidthFraction * 0.5
            withAnimation(.easeInOut(duration: 2.0)) {
                interactionOffset = CGSize(width: targetX - crawlOffset, height: 0)
            }
            showReaction(CreatureReactions.interactionReaction(creature: .hermitCrab, type: type))

        case .interacting(let type):
            // 播放互动微动画 — 蟹的反应更内向
            switch type {
            case .bump:
                // 碰撞: 缩壳 + 弹回
                withAnimation(.spring(response: 0.08, dampingFraction: 0.5)) {
                    shellRetracted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                        shellRetracted = false
                        interactionOffset.width += (facingLeft ? -6 : 6)
                    }
                }
            case .highFive:
                // 碰拳: 壳摇晃 + 小 scale
                withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                    transitionScale = 1.08
                    interactionOffset.width += (facingLeft ? 3 : -3)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        transitionScale = 1.0
                    }
                }
            case .play:
                // 绕圈: 蟹小幅左右挪动
                withAnimation(.easeInOut(duration: 0.7).repeatCount(3, autoreverses: true)) {
                    interactionOffset.width += 5
                }
            case .nuzzle:
                // 依偎: 靠近 + 轻微壳晃
                withAnimation(.easeInOut(duration: 0.9).repeatCount(2, autoreverses: true)) {
                    interactionOffset.width -= 3
                }
            }

        case .retreating:
            // 返回原位
            withAnimation(.easeInOut(duration: 1.5)) {
                interactionOffset = .zero
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                canCrawl = state.task.canWalk && !isDead && !reduceMotion
                if canCrawl { scheduleCrawl() }
            }

        case .idle:
            if interactionOffset != .zero {
                withAnimation(.easeOut(duration: 0.3)) {
                    interactionOffset = .zero
                }
            }
        }
    }
}
