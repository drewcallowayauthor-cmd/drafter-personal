import SwiftUI

/// A `Menu`-backed dropdown for a fixed set of choices, styled to match
/// `NocturneField`'s label/surface/border look. A native `Picker` was ruled out — its
/// macOS popup-button chrome doesn't match the rest of Nocturne, and can't be
/// restyled from SwiftUI.
struct NocturneDropdown<T: Hashable>: View {
    var label: String
    @Binding var selection: T
    let options: [T]
    let title: (T) -> String

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(title(option)) { selection = option }
                }
            } label: {
                HStack {
                    Text(title(selection))
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
        }
    }

    private var borderColor: SwiftUI.Color {
        isHovering ? Theme.Color.text.opacity(0.45) : Theme.Color.divider
    }
}
