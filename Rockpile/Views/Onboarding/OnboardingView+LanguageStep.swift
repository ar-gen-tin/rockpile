import SwiftUI

// MARK: - 步骤 0: 语言选择

extension OnboardingView {
    var languageSelectionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Rockpile").font(.system(size: 28, weight: .bold))
            Text("🐚 + 🦞 — Your Notch Bar Companions")
                .font(.system(size: 13)).foregroundColor(.secondary)

            Spacer().frame(height: 12)

            Text(L10n.s("onboard.selectLanguage"))
                .font(.system(size: 16, weight: .medium))

            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                    languageCard(lang)
                }
            }
            .padding(.horizontal, 60)

            Spacer()

            HStack {
                Spacer()
                Button(L10n.s("onboard.next")) {
                    step = .roleAndWelcome
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    func languageCard(_ lang: AppLanguage) -> some View {
        let isSelected = L10n.language == lang
        return Button {
            AppSettings.appLanguage = lang.rawValue
            languageRefresh += 1
        } label: {
            HStack(spacing: 12) {
                Text(lang.flag)
                    .font(.system(size: 24))
                Text(lang.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
