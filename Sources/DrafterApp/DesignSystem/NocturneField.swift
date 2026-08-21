import SwiftUI

/// Mirrors Nocturne's `.field`/`.input` — a labeled text field with the surface background and
/// divider border that brightens to accent on hover/focus.
struct NocturneField: View {
    var label: String
    var placeholder: String = ""
    @Binding var text: String
    var isSecure = false
    /// When set, the field grows vertically within this line range instead of staying
    /// single-line (e.g. a project's Description field).
    var multilineRange: ClosedRange<Int>?
    /// Optional external focus binding, e.g. for autofocusing a prompt sheet's field on
    /// appear — `.focused()` applied to this view from the outside wouldn't reach the
    /// internal `TextField` it wraps.
    var externalFocus: FocusState<Bool>.Binding?

    @FocusState private var internalFocus: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            fieldContent
                .textFieldStyle(.plain)
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.Color.text)
                .tint(Theme.Color.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, multilineRange == nil ? 0 : 8)
                .frame(minHeight: 36)
                .background(Theme.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .focused(externalFocus ?? $internalFocus)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovering)
        }
    }

    private var isFocused: Bool {
        externalFocus?.wrappedValue ?? internalFocus
    }

    @ViewBuilder
    private var fieldContent: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else if let multilineRange {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(multilineRange)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private var borderColor: SwiftUI.Color {
        if isFocused { return Theme.Color.accent }
        if isHovering { return Theme.Color.text.opacity(0.45) }
        return Theme.Color.divider
    }
}
