import SwiftUI

// MARK: - Underwater Sprite (Interactive)

struct UnderwaterSpriteView: View {
    let state: ClawState
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat
    let glowOpacity: Double
    var isDead: Bool = false
    var tokenTracker: TokenTracker?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spriteSize: CGFloat = 80
    private static let usableWidthFraction: CGFloat = 0.8
    private static let leftMarginFraction: CGFloat = 0.1

    /// 睡眠时降落到沙面
    /// 几何: spriteSize=80, scale=1.25, content rows 10-49
    /// content_bottom = (H - |yOffset| - 80) + 49*1.25
    /// sand_surface ≈ H-30 → yOffset=-11 使 content_bottom ≈ sand_surface
    private var effectiveYOffset: CGFloat {
        state == .sleeping ? -11 : yOffset
    }

    // ── Swimming (arc path) ──
    @State private var swimOffset: CGFloat = 0
    @State private var swimVertical: CGFloat = 0  // 弧形路径的垂直分量
    @State private var facingLeft: Bool = false
    @State private var canSwim: Bool = false

    // ── Entry animation ──
    @State private var entryScale: CGFloat = 0.3
    @State private var showSplash: Bool = false

    // ── State transition ──
    @State private var transitionScale: CGFloat = 1.0
    @State private var transitionCounter: Int = 0

    // ── Interaction: tap reaction ──
    @State private var jumpOffset: CGFloat = 0
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
            // 💀 Ghost effect — floats up on death
            GhostSpriteView(state: state, size: Self.spriteSize, isDead: isDead)
                .allowsHitTesting(false)

            // 🫧 Breath bubbles from mouth
            BreathBubblesView(isDead: isDead, task: state.task, spriteSize: Self.spriteSize,
                              oxygenStress: tokenTracker?.oxygenStress ?? 0)

            // Main sprite container with all overlays
            ZStack {
                // 🦞 Core sprite
                CrawfishSpriteView(
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
            .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            // ── Hit area: frame + contentShape on sprite core ──
            .frame(width: Self.spriteSize, height: Self.spriteSize)
            .contentShape(Rectangle())
            // ── Gestures: drag (min distance avoids tap conflict) ──
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            canSwim = false
                            InteractionCoordinator.shared.cancelInteraction()
                        }
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
                            dragBase.height += 1.5
                        }
                        if (state.task.canWalk || manuallyAwake) && !isDead && !reduceMotion {
                            canSwim = true
                            scheduleSwim()
                        }
                        updateInteractionEligibility()
                    }
            )
            // ── Tap gestures: double-tap first, then single-tap ──
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
            .onTapGesture(count: 1) {
                handleSingleTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                handleLongPress()
            }
            // ── Context menu for feeding ──
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
            .accessibilityLabel("\(L10n.s("sprite.accessCrawfish")), \(state.displayName)")
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
                            .fill(Color.orange.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .offset(y: -Self.spriteSize * 0.65)
                    .opacity(reactionOpacity)
                    .allowsHitTesting(false)
            }

            // 📋 Info card (long-press) — compact tooltip, offset to the right
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

            // 💦 Entry splash particles
            SplashParticleView(
                isActive: showSplash,
                origin: CGPoint(x: Self.spriteSize, y: Self.spriteSize * 0.6),
                size: Self.spriteSize * 2.5
            )

            // 🍤 Food particles (feeding)
            FoodParticleView(
                triggerCounter: feedCounter,
                targetY: Self.spriteSize * 0.4,
                size: Self.spriteSize * 2
            )
            .offset(y: -Self.spriteSize * 0.3)

            // 📱 Remote activity bubble (展开后从 header 转移到小龙虾)
            ActivityBadgeView(
                bubbleCount: RemoteActivityTracker.shared.bubbleCount,
                isBubbleShowing: RemoteActivityTracker.shared.isBubbleShowing,
                bubbleTrigger: RemoteActivityTracker.shared.bubbleTrigger,
                spriteSize: Self.spriteSize
            )
        }
        .shadow(color: Color(red: 0.3, green: 0.6, blue: 0.8).opacity(glowOpacity * 0.5), radius: 6)
        .offset(x: xOffset + swimOffset + interactionOffset.width + dragBase.width + dragOffset.width,
                y: effectiveYOffset + swimVertical + jumpOffset + interactionOffset.height + dragBase.height + dragOffset.height)
        // ── Lifecycle ──
        .onAppear {
            if reduceMotion {
                entryScale = 1.0
            } else {
                // Entry animation: scale 0.3 → 1.0 with spring
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    entryScale = 1.0
                }
                // Trigger splash particles slightly after entry begins
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showSplash = true
                }
            }
            // Start swimming if possible (disabled when reduceMotion)
            canSwim = state.task.canWalk && !isDead && !reduceMotion
            if canSwim {
                scheduleSwim()
            }
            // 📱 展开时消费远程活动通知 → 触发小龙虾气泡
            RemoteActivityTracker.shared.consumeForBubble()
            // 互动: 注册可互动状态
            updateInteractionEligibility()
        }
        // ── State change: transition bounce + FX ──
        .onChange(of: state.task) { _, newTask in
            if !reduceMotion {
                // Bounce: 1.0 → 1.15 → 1.0
                withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                    transitionScale = 1.15
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        transitionScale = 1.0
                    }
                }
                // Trigger star particles
                transitionCounter += 1
            }
            // Update swimming
            canSwim = newTask.canWalk && !isDead && !reduceMotion
            if canSwim {
                scheduleSwim()
            }
            updateInteractionEligibility()
        }
        .onChange(of: isDead) { _, dead in
            canSwim = state.task.canWalk && !dead && !reduceMotion
            updateInteractionEligibility()
        }
        // ── Cross-creature interaction phase observer ──
        .onChange(of: InteractionCoordinator.shared.phase) { _, newPhase in
            handleInteractionPhase(newPhase)
        }
    }

    // MARK: - Swimming Logic

    private func scheduleSwim() {
        let delay = Double.random(in: 8.0...15.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard canSwim else { return }
            performSwim()
        }
    }

    private func performSwim() {
        // stress 高时: 幅度缩小 (疲惫)，速度减慢
        let stress = tokenTracker?.oxygenStress ?? 0
        let maxOffset: CGFloat = 25 * CGFloat(max(0.3, 1.0 - stress))
        let target = CGFloat.random(in: -maxOffset...maxOffset)
        facingLeft = target < swimOffset

        let duration = Double.random(in: 1.0...2.0) * (1.0 + stress * 0.5)
        let halfDuration = duration / 2

        // 弧形路径: 上下波动，模拟水中游泳
        let arcHeight = CGFloat.random(in: -8...8)
        withAnimation(.easeIn(duration: halfDuration)) {
            swimOffset = (swimOffset + target) / 2
            swimVertical = arcHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + halfDuration) {
            withAnimation(.easeOut(duration: halfDuration)) {
                swimOffset = target
                swimVertical = 0
            }
        }

        // Schedule next swim after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            guard canSwim else { return }
            scheduleSwim()
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

        // 点击唤醒: 睡眠状态下点击 → 立即开始游泳 60 秒
        if !canSwim && !isDead && !reduceMotion {
            manuallyAwake = true
            canSwim = true
            performSwim()   // ← 立即移动，不等 8-15 秒
            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                guard manuallyAwake else { return }
                manuallyAwake = false
                if !state.task.canWalk {
                    canSwim = false
                }
            }
        }

        // Jump reaction — 小龙虾弹跳（外向性格）
        withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
            jumpOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                jumpOffset = 0
            }
        }

        // State-aware reaction text
        showReaction(CreatureReactions.tapReaction(creature: .crawfish, task: state.task, isDead: isDead))

        // Squash-stretch effect
        withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
            transitionScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                transitionScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tapCooldown = false }
    }

    private func handleDoubleTap() {
        guard !isDead else { return }
        heartCounter += 1

        // State-aware love reaction
        showReaction(CreatureReactions.loveReaction(creature: .crawfish, task: state.task, isDead: isDead), duration: 1.5)

        // Bounce
        withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
            transitionScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
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
            // Overfed rejection feedback
            if wasOverfed || tracker.isOverfed {
                showReaction(CreatureReactions.feedReaction(creature: .crawfish, isOverfed: true))
                // Queasy shake
                withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) {
                    transitionScale = 0.95
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                        transitionScale = 1.0
                    }
                }
            }
            return
        }

        feedCounter += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                feedReactionScale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    feedReactionScale = 1.0
                }
            }

            let isNowOverfed = tracker.isOverfed
            showReaction(CreatureReactions.feedReaction(creature: .crawfish, isOverfed: isNowOverfed), duration: 1.5)
        }
    }

    /// Triple-tap punishment: shake + angry reaction + -2% O₂
    private func handlePunishment() {
        isAngry = true
        showReaction(CreatureReactions.punishReaction(creature: .crawfish), duration: 2.0)

        // Angry shake sequence
        let shakeSequence: [(CGFloat, Double)] = [
            (-4, 0.05), (4, 0.05), (-3, 0.05), (3, 0.05), (-2, 0.05), (0, 0.1)
        ]
        var delay = 0.0
        for (offset, dur) in shakeSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: dur)) { jumpOffset = offset }
            }
            delay += dur
        }

        // Penalty: reduce feed bonus (effectively -2% O₂)
        if let tracker = tokenTracker {
            let penalty = Int(Double(tracker.oxygenLevel > 0 ? 1 : 0) * Double(max(1, Int(Double(AppSettings.localOxygenTankCapacity) * 0.02))))
            tracker.feedBonusTokens = max(0, tracker.feedBonusTokens - penalty)
        }

        // Clear angry after 3s
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

    // MARK: - Cross-Creature Interaction (小龙虾侧)

    private func updateInteractionEligibility() {
        let eligible = (state.task == .idle || state.task == .sleeping) && !isDead && !isDragging && !reduceMotion
        InteractionCoordinator.shared.crawfishCanInteract = eligible
    }

    private func handleInteractionPhase(_ phase: InteractionCoordinator.Phase) {
        let coordinator = InteractionCoordinator.shared

        switch phase {
        case .approaching(let type):
            // 暂停游泳，向会合点下沉
            canSwim = false
            let meetX = coordinator.meetingX
            let targetX = (meetX - xPosition) * totalWidth * Self.usableWidthFraction * 0.5
            // 小龙虾下沉到蟹的高度 (y 靠近 crab 的 -25 位置)
            let targetY: CGFloat = -yOffset + (-25)
            withAnimation(.easeInOut(duration: 2.0)) {
                interactionOffset = CGSize(width: targetX - swimOffset, height: targetY)
            }
            showReaction(CreatureReactions.interactionReaction(creature: .crawfish, type: type))

        case .interacting(let type):
            // 播放互动微动画
            switch type {
            case .bump:
                // 碰撞: 向后弹 8pt
                withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                    interactionOffset.width += (facingLeft ? 8 : -8)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        interactionOffset.width -= (facingLeft ? 4 : -4)
                    }
                }
            case .highFive:
                // 碰拳: 小幅前冲 + scale pop
                withAnimation(.spring(response: 0.12, dampingFraction: 0.4)) {
                    transitionScale = 1.15
                    interactionOffset.width += (facingLeft ? -3 : 3)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        transitionScale = 1.0
                    }
                }
            case .play:
                // 绕圈: 小幅上下摆动
                withAnimation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true)) {
                    interactionOffset.height -= 6
                }
            case .nuzzle:
                // 依偎: 轻微左右摇摆
                withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                    interactionOffset.width += 4
                }
            }

        case .retreating:
            // 返回原位
            withAnimation(.easeInOut(duration: 1.5)) {
                interactionOffset = .zero
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                canSwim = state.task.canWalk && !isDead && !reduceMotion
                if canSwim { scheduleSwim() }
            }

        case .idle:
            // 确保清理
            if interactionOffset != .zero {
                withAnimation(.easeOut(duration: 0.3)) {
                    interactionOffset = .zero
                }
            }
        }
    }
}
