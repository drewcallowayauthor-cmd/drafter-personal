import SwiftUI

/// Mirrors Nocturne's `.tag`/`.tag-accent`/`.tag-accent-2`/`.tag-neutral`/`.tag-outline` — used
/// for the editor toolbar's "Synced" pill and similar small status labels.
struct NocturneTag: View {
    enum Style {
        case accent, accent2, neutral, outline
    }

    var text: String
    var style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .tracking(0.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75, style: .continuous)
                    .stroke(style == .outline ? Theme.Color.accent : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75, style: .continuous))
    }

    private var background: SwiftUI.Color {
        switch style {
        case .accent: Theme.Color.accent800
        case .accent2: Theme.Color.accent2800
        case .neutral: Theme.Color.neutral800
        case .outline: .clear
        }
    }

    private var foreground: SwiftUI.Color {
        switch style {
        case .accent: Theme.Color.accent100
        case .accent2: Theme.Color.accent2100
        case .neutral: Theme.Color.neutral100
        case .outline: Theme.Color.accent
        }
    }
}
