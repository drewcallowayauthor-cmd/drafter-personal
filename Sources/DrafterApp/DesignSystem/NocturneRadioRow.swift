import SwiftUI

/// Mirrors Nocturne's `.radio` — used by New Project's Version Control picker (the prototype's
/// 2a-style radios, not 2b's cards, per the design handoff).
struct NocturneRadioRow<Content: View>: View {
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(dotBorderColor, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 1)
                content()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var dotBorderColor: SwiftUI.Color {
        (isSelected || isHovering) ? Theme.Color.accent : Theme.Color.divider
    }
}
