import SwiftUI

/// A single-field text prompt — §8.2's "New Chapter" and "New Scene" only need a
/// title, so this is shared rather than duplicating `NewProjectSheet`'s shape for one
/// field.
struct TextPromptSheet: View {
    let title: String
    let fieldLabel: String
    let confirmLabel: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var isFieldFocused: Bool

    /// `initialText` pre-fills the field — used by the binder's "Rename…" to seed the
    /// current title, rather than making the user retype it.
    init(
        title: String,
        fieldLabel: String,
        confirmLabel: String,
        initialText: String = "",
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.confirmLabel = confirmLabel
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NocturneSheet(title: title, width: 360, onClose: onCancel) {
            NocturneField(label: fieldLabel, text: $text, externalFocus: $isFieldFocused)
        } footer: {
            Button("Cancel", action: onCancel)
                .buttonStyle(.nocturneSecondary)
            Button(confirmLabel) { onSubmit(text) }
                .buttonStyle(.nocturnePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { isFieldFocused = true }
    }
}
