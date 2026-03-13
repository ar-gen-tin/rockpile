import SwiftUI

/// Compact O₂ bar for the dual-source dashboard — one per creature type.
///
/// Layout: 🐚 [████████░░░░] 67%  280K/420K
/// Height: ~24pt (vs original ~40pt)
struct CompactOxygenBarView: View {
    let tracker: TokenTracker
    let creatureType: CreatureType

    private var level: Double { tracker.oxygenLevel }
    private var percent: Int { tracker.oxygenPercent }

    private var accentColor: Color {
        DS.Semantic.remoteAccent
    }

    private var barColor: Color {
        switch level {
        case 0.6...:    return accentColor
        case 0.3..<0.6: return DS.Semantic.warning
        default:        return DS.Semantic.danger
        }
    }

    private var needsBlink: Bool {
        tracker.isDead || (level < 0.1 && !tracker.isDead)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !needsBlink)) { timeline in
            let blinkOn = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0

            HStack(spacing: DS.Space.sm) {
                // Pixel bar (creature icon removed — already shown in DualSourceInfoRow above)
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let blockSize: CGFloat = DS.Compact.blockSize
                    let gap: CGFloat = DS.Compact.blockGap
                    let blockCount = Int(totalWidth / (blockSize + gap))
                    let filledBlocks = Int(Double(blockCount) * level)

                    HStack(spacing: gap) {
                        ForEach(0..<blockCount, id: \.self) { i in
                            Rectangle()
                                .fill(i < filledBlocks ? barColor : DS.Surface.raised)
                                .frame(width: blockSize)
                        }
                    }
                    .frame(height: 8)
                    .opacity(level < 0.1 && !tracker.isDead ? (blinkOn ? 1 : DS.Opacity.tertiary) : 1)
                }
                .frame(height: 8)

                // Percentage
                if tracker.isDead {
                    Text("K.O.")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(DS.Semantic.danger)
                        .opacity(blinkOn ? 1 : DS.Opacity.tertiary)
                        .frame(width: DS.Compact.percentWidth, alignment: .trailing)
                } else {
                    Text("\(percent)%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(barColor)
                        .frame(width: DS.Compact.percentWidth, alignment: .trailing)
                }

                // Token count / balance
                if let balance = tracker.remainingBalanceUSD {
                    Text(TokenTracker.formatBalance(balance))
                        .font(DS.Font.monoTiny)
                        .foregroundColor(DS.Semantic.success)
                        .frame(width: DS.Compact.tokenWidth, alignment: .trailing)
                } else {
                    Text(TokenTracker.formatTokens(tracker.effectiveDailyUsed))
                        .font(DS.Font.monoTiny)
                        .foregroundColor(DS.TextColor.tertiary)
                        .frame(width: DS.Compact.tokenWidth, alignment: .trailing)
                }
            }
        }
        .frame(height: DS.Compact.barHeight)
    }
}
