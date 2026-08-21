import SwiftUI

/// Mirrors Nocturne's `.seg`/`.seg-opt` — used by Compile's target picker (EPUB/Print/DOCX) and
/// Project Settings' Drafting/Revising/Complete status control. Options are bordered segments,
/// not native radio buttons.
struct NocturneSegmentedControl<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    var options: [Value]
    @ViewBuilder var label: (Value) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                SegmentButton(isSelected: selection == option, isFirst: index == 0) {
                    selection = option
                } content: {
                    label(option)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Color.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

private struct SegmentButton<Content: View>: View {
    var isSelected: Bool
    var isFirst: Bool
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(Theme.Font.body(13))
                .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.text)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(isHovering && !isSelected ? Theme.Color.text.opacity(0.07) : .clear)
                .overlay(
                    Rectangle()
                        .inset(by: 0.5)
                        .stroke(isSelected ? Theme.Color.accent : .clear, lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    if !isFirst {
                        Rectangle().fill(Theme.Color.divider).frame(width: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}
