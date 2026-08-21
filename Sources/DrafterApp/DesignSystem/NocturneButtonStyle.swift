import SwiftUI

/// Mirrors Nocturne's `.btn`/`.btn-primary`/`.btn-secondary`/`.btn-ghost`/`.btn-icon` — buttons
/// are outlined, never solid-filled, per the design system's direction.
struct NocturneButtonStyle: ButtonStyle {
    enum Variant {
        case primary, secondary, ghost, icon
    }

    var variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        NocturneButtonBody(configuration: configuration, variant: variant)
    }
}

extension ButtonStyle where Self == NocturneButtonStyle {
    static var nocturnePrimary: NocturneButtonStyle { NocturneButtonStyle(variant: .primary) }
    static var nocturneSecondary: NocturneButtonStyle { NocturneButtonStyle(variant: .secondary) }
    static var nocturneGhost: NocturneButtonStyle { NocturneButtonStyle(variant: .ghost) }
    static var nocturneIcon: NocturneButtonStyle { NocturneButtonStyle(variant: .icon) }
}

private struct NocturneButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: NocturneButtonStyle.Variant
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.Font.heading(14))
            .foregroundStyle(foregroundColor)
            .padding(.vertical, variant == .icon ? 0 : Theme.Spacing.space2)
            .padding(.horizontal, horizontalPadding)
            .frame(width: variant == .icon ? 36 : nil, height: variant == .icon ? 36 : nil)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .ghost: Theme.Spacing.space1
        case .icon: 0
        case .primary, .secondary: Theme.Spacing.space3 * 1.2
        }
    }

    private var foregroundColor: SwiftUI.Color {
        switch variant {
        case .primary, .ghost: Theme.Color.accent
        case .secondary, .icon: Theme.Color.text
        }
    }

    private var borderColor: SwiftUI.Color {
        switch variant {
        case .primary: Theme.Color.accent
        case .secondary, .icon: Theme.Color.divider
        case .ghost: .clear
        }
    }

    private var backgroundColor: SwiftUI.Color {
        let intensity: Double = configuration.isPressed ? pressedOpacity : (isHovering ? hoverOpacity : 0)
        guard intensity > 0 else { return .clear }
        let tint: SwiftUI.Color = (variant == .secondary || variant == .icon) ? Theme.Color.text : Theme.Color.accent
        return tint.opacity(intensity)
    }

    private var hoverOpacity: Double {
        switch variant {
        case .primary: 0.12
        case .secondary, .icon: 0.07
        case .ghost: 0.10
        }
    }

    private var pressedOpacity: Double {
        switch variant {
        case .primary: 0.22
        case .secondary, .icon: 0.14
        case .ghost: 0.18
        }
    }
}
