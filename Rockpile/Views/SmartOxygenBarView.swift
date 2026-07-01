import SwiftUI

/// Smart O₂ bar — shows 1 bar if both creatures use same API, 2 bars if different.
struct SmartOxygenBarView: View {
    let localTracker: TokenTracker
    let remoteTracker: TokenTracker

    private var isSameProvider: Bool {
        let local = AIProviderDetector.detectLocalProvider()
        let remote = AIProviderDetector.detectRemoteProvider()
        if local == .unknown && remote == .unknown { return true }
        if remote == .unknown { return true }
        return local == remote
    }

    var body: some View {
        VStack(spacing: 4) {
            if isSameProvider {
                singleBar(
                    tracker: localTracker,
                    label: AIProviderDetector.detectLocalProvider().displayName,
                    color: DS.Semantic.success
                )
            } else {
                singleBar(
                    tracker: localTracker,
                    label: AIProviderDetector.detectLocalProvider().displayName,
                    color: DS.Semantic.success,
                    icon: "crab"
                )
                singleBar(
                    tracker: remoteTracker,
                    label: AIProviderDetector.detectRemoteProvider().displayName,
                    color: DS.Semantic.warning,
                    icon: "lobster"
                )
            }
        }
    }

    @ViewBuilder
    private func singleBar(
        tracker: TokenTracker,
        label: String,
        color: Color,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Text(icon == "crab" ? "🐚" : "🦞")
                    .font(.system(size: 10))
            }

            Text(label)
                .font(DS.Font.caption)
                .foregroundColor(DS.TextColor.tertiary)
                .frame(width: icon != nil ? 48 : 56, alignment: .leading)

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(tracker: tracker, accent: color))
                        .frame(width: max(0, geo.size.width * tracker.oxygenLevel), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(Int(tracker.oxygenPercent))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(barColor(tracker: tracker, accent: color))
                .frame(width: 32, alignment: .trailing)

            Text(tracker.etaText ?? "")
                .font(DS.Font.caption)
                .foregroundColor(DS.TextColor.muted)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 18)
    }

    private func barColor(tracker: TokenTracker, accent: Color) -> Color {
        if tracker.isDead { return DS.Semantic.danger }
        if tracker.oxygenLevel < 0.15 { return DS.Semantic.danger }
        if tracker.oxygenLevel < 0.3 { return DS.Semantic.warning }
        return accent
    }
}
