import SwiftUI

// MARK: - Design Token System
// Based on Impeccable design principles:
// - 4pt spacing base (not 8pt — more granular)
// - Modular type scale with clear hierarchy (5 sizes max)
// - Semantic opacity levels (not arbitrary .opacity(0.XX))
// - Consistent color roles

enum DS {

    // MARK: - Spacing (4pt base)
    // 4, 8, 12, 16, 24, 32

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Typography Scale
    // 5-size system with clear ratio contrast (≥ 1.25x between levels)
    // 9 → 10 → 11 → 13 → 15

    enum Font {
        /// Tiny labels in compact UI — 8pt
        static let tiny = SwiftUI.Font.system(size: 8)
        /// Captions, metadata timestamps — 9pt mono
        static let caption = SwiftUI.Font.system(size: 9, design: .monospaced)
        /// Secondary info, labels — 10pt
        static let secondary = SwiftUI.Font.system(size: 10)
        /// Body text, activity details — 11pt
        static let body = SwiftUI.Font.system(size: 11)
        /// Subheadings, status — 12pt medium
        static let subhead = SwiftUI.Font.system(size: 12, weight: .medium)
        /// Section titles — 14pt semibold
        static let title = SwiftUI.Font.system(size: 14, weight: .semibold)

        /// Monospaced variants
        static let monoTiny = SwiftUI.Font.system(size: 8, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 9, design: .monospaced)
        static let mono = SwiftUI.Font.system(size: 10, design: .monospaced)
        static let monoBody = SwiftUI.Font.system(size: 11, design: .monospaced)
        static let monoBold = SwiftUI.Font.system(size: 11, weight: .bold, design: .monospaced)
    }

    // MARK: - Semantic Opacity Levels
    // Only 5 levels — eliminates random .opacity(0.XX) scattered everywhere
    // On dark backgrounds: brighter = more important

    enum Opacity {
        /// Primary text, active elements — fully readable
        static let primary: Double = 0.88
        /// Secondary text, labels — clearly visible but subordinate
        static let secondary: Double = 0.6
        /// Tertiary, metadata, timestamps — subtle
        static let tertiary: Double = 0.38
        /// Dividers, borders, disabled — barely there
        static let muted: Double = 0.15
        /// Ghost elements, background fills
        static let ghost: Double = 0.08
    }

    // MARK: - Text Colors (Semantic)
    // Apply on white base for dark theme

    enum TextColor {
        static let primary = Color.white.opacity(Opacity.primary)
        static let secondary = Color.white.opacity(Opacity.secondary)
        static let tertiary = Color.white.opacity(Opacity.tertiary)
        static let muted = Color.white.opacity(Opacity.muted)
    }

    // MARK: - Semantic Colors
    // Consistent role-based colors across the entire app

    enum Semantic {
        static let success = Color(red: 0.2, green: 0.85, blue: 0.3)
        static let warning = Color(red: 0.95, green: 0.75, blue: 0.1)
        static let danger = Color(red: 0.95, green: 0.2, blue: 0.15)
        static let info = Color.cyan
        static let accent = Color.cyan
        static let working = Color.green
        static let thinking = Color.cyan
        static let toolCall = Color.orange

        // Dual ecosystem accent colors
        static let localAccent = Color.cyan            // 寄居蟹 / 本地
        static let remoteAccent = Color.orange         // 小龙虾 / 远程
    }

    // MARK: - Compact UI Tokens (v2.0 dashboard)

    enum Compact {
        static let barHeight: CGFloat = 24       // 紧凑 O₂ 条高度
        static let blockSize: CGFloat = 3        // 紧凑像素块
        static let blockGap: CGFloat = 1         // 像素块间距
        static let cardPadding: CGFloat = 8      // 数据卡片内边距
        static let cardRadius: CGFloat = 8       // 数据卡片圆角
        static let percentWidth: CGFloat = 28    // 百分比标签宽度
        static let tokenWidth: CGFloat = 38      // token 计数/余额宽度
        static let burnRateWidth: CGFloat = 48   // 消耗率标签宽度 "↑2.1K/m"
        static let etaWidth: CGFloat = 32        // ETA 标签宽度 "~3.2h"
        static let dataAreaWidth: CGFloat = 50   // 进度条右侧数据区固定宽度（统一两边条块宽度）
    }

    // MARK: - Surface Colors
    // Dark theme depth via surface lightness (not shadows)

    enum Surface {
        /// Base black background
        static let base = Color.black
        /// Slightly elevated surface
        static let raised = Color.white.opacity(Opacity.ghost)    // 0.08
        /// Selected/active element background
        static let selected = Color.cyan.opacity(0.3)
        /// Divider line
        static let divider = Color.white.opacity(Opacity.muted)   // 0.15
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Section Header Style Helper
    static func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(TextColor.tertiary)
            .tracking(1.2)
    }
}
