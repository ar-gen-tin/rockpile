import SwiftUI

/// Permission request banner — shows tool name, input summary, Allow/Deny buttons.
/// Appears as an overlay in NotchContentView when permission requests arrive.
struct PermissionBannerView: View {
    let request: PermissionHandler.PermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void

    @State private var timeRemaining: TimeInterval

    init(request: PermissionHandler.PermissionRequest, onAllow: @escaping () -> Void, onDeny: @escaping () -> Void) {
        self.request = request
        self.onAllow = onAllow
        self.onDeny = onDeny
        self._timeRemaining = State(initialValue: PermissionHandler.shared.timeRemaining(for: request))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            // Tool name + countdown
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(DS.Semantic.warning)
                    .font(.system(size: 14))

                Text(request.toolName)
                    .font(DS.Font.monoBold)
                    .foregroundColor(DS.TextColor.primary)

                Spacer()

                // Countdown
                Text(formatTime(timeRemaining))
                    .font(DS.Font.monoSmall)
                    .foregroundColor(DS.TextColor.tertiary)
            }

            // Input summary
            if !request.inputSummary.isEmpty {
                Text(request.inputSummary)
                    .font(DS.Font.mono)
                    .foregroundColor(DS.TextColor.secondary)
                    .lineLimit(2)
            }

            // Allow / Deny buttons
            HStack(spacing: DS.Space.sm) {
                Button {
                    onAllow()
                } label: {
                    Text(L10n.s("perm.allow"))
                        .font(DS.Font.monoBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(DS.Semantic.success)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onDeny()
                } label: {
                    Text(L10n.s("perm.deny"))
                        .font(DS.Font.monoBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .fill(DS.Semantic.danger)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Semantic.warning.opacity(0.5), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.7)),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        ))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            timeRemaining = PermissionHandler.shared.timeRemaining(for: request)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
