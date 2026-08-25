import SwiftUI

/// Ports the Nocturne design system's tokens (`docs/design_handoff_drafter_redesign/design-system/
/// nocturne/styles.css`) into Swift. This is the single source of truth for color, spacing, radius,
/// and type in the revamped UI — screens should reference `Theme.*` rather than hardcoding values.
enum Theme {
    enum Color {
        static let bg = SwiftUI.Color(hex: 0x161826)
        static let surface = SwiftUI.Color(hex: 0x232532)
        static let text = SwiftUI.Color(hex: 0xE9E9ED)
        static let accent = SwiftUI.Color(hex: 0x9184D9)
        static let accent2 = SwiftUI.Color(hex: 0xA7A1DB)
        /// `color-mix(in srgb, #e9e9ed 16%, transparent)`.
        static let divider = text.opacity(0.16)

        static let neutral100 = SwiftUI.Color(hex: 0xF3F5FE)
        static let neutral200 = SwiftUI.Color(hex: 0xE4E7F5)
        static let neutral300 = SwiftUI.Color(hex: 0xCFD3E5)
        static let neutral400 = SwiftUI.Color(hex: 0xB2B6CA)
        static let neutral500 = SwiftUI.Color(hex: 0x9397AB)
        static let neutral600 = SwiftUI.Color(hex: 0x75798C)
        static let neutral700 = SwiftUI.Color(hex: 0x595D6C)
        static let neutral800 = SwiftUI.Color(hex: 0x3F424D)
        static let neutral900 = SwiftUI.Color(hex: 0x292B31)

        static let accent100 = SwiftUI.Color(hex: 0xF5F4FF)
        static let accent200 = SwiftUI.Color(hex: 0xE7E5FE)
        static let accent300 = SwiftUI.Color(hex: 0xD2CEFD)
        static let accent400 = SwiftUI.Color(hex: 0xB5ABFC)
        static let accent500 = SwiftUI.Color(hex: 0x968AE0)
        static let accent600 = SwiftUI.Color(hex: 0x796CBF)
        static let accent700 = SwiftUI.Color(hex: 0x5D5294)
        static let accent800 = SwiftUI.Color(hex: 0x423A6A)
        static let accent900 = SwiftUI.Color(hex: 0x2B2741)

        static let accent2100 = SwiftUI.Color(hex: 0xF5F4FF)
        static let accent2200 = SwiftUI.Color(hex: 0xE7E5FE)
        static let accent2300 = SwiftUI.Color(hex: 0xD2CEFD)
        static let accent2400 = SwiftUI.Color(hex: 0xB5AFE8)
        static let accent2500 = SwiftUI.Color(hex: 0x9690C9)
        static let accent2600 = SwiftUI.Color(hex: 0x7972A9)
        static let accent2700 = SwiftUI.Color(hex: 0x5C5783)
        static let accent2800 = SwiftUI.Color(hex: 0x423E5D)
        static let accent2900 = SwiftUI.Color(hex: 0x2B293A)

        /// `color-mix(in srgb, var(--color-text) 55%, transparent)` — `.text-muted`.
        static let textMuted = text.opacity(0.55)

        /// Not part of the Nocturne handoff's token set — added for the diff view's
        /// addition/deletion coloring, which the handoff spec'd in neutral/accent tones
        /// (§ History & diff) but proved too muted to scan at a glance. Tuned to sit
        /// in Nocturne's saturation/lightness range rather than a stock red/green, so
        /// they read as part of the same palette against `bg`/`surface`.
        static let diffAdded = SwiftUI.Color(hex: 0x7CC98A)
        static let diffRemoved = SwiftUI.Color(hex: 0xE28089)
    }

    enum Spacing {
        static let space1: CGFloat = 2.8
        static let space2: CGFloat = 5.6
        static let space3: CGFloat = 8.4
        static let space4: CGFloat = 11.2
        static let space6: CGFloat = 16.8
        static let space8: CGFloat = 22.4
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 14
    }

    enum Font {
        /// Inter isn't bundled with the app, so headings fall back to the system font at the
        /// same weight/size the spec calls for. Vendoring the Inter font files is tracked as a
        /// follow-up rather than blocking the rest of the revamp on it.
        static func heading(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .medium)
        }

        static func body(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size)
        }
    }

    enum Shadow {
        /// `--shadow-sm`: a 1px hairline edge, no ambient blur.
        static func sm(_ content: some View) -> some View {
            content.overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.neutral800, lineWidth: 1))
        }

        /// `--shadow-md`: 1px edge + soft ambient shadow.
        static func md(_ content: some View) -> some View {
            content
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.neutral700, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 9, x: 0, y: 6)
        }

        /// `--shadow-lg`: 1px edge + larger ambient shadow, used by modal sheets.
        static func lg(_ content: some View) -> some View {
            content
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.neutral500, lineWidth: 1))
                .shadow(color: .black.opacity(0.65), radius: 20, x: 0, y: 16)
        }
    }
}

extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
