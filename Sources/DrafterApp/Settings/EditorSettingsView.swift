import SwiftUI

/// §12's Editor pane: font size, line height, measured width, and typewriter scrolling —
/// all live-applied to any open scene via `AppPreferences`, since `ContentView` reads
/// these same properties on every `SceneTextView` render. Theme, font family, and focus
/// mode are cut for this pass (no existing abstraction to hang them on).
struct EditorSettingsView: View {
    @Bindable var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            steppedRow(
                label: "Font Size",
                value: Binding(
                    get: { Int(prefs.editorFontSize) },
                    set: { prefs.editorFontSize = Double($0) }
                ),
                range: 10...28,
                suffix: "pt"
            )
            steppedRow(
                label: "Line Height",
                value: Binding(
                    get: { Int((prefs.editorLineHeightMultiple * 10).rounded()) },
                    set: { prefs.editorLineHeightMultiple = Double($0) / 10 }
                ),
                range: 10...20,
                suffix: "×",
                displayTransform: { String(format: "%.1f", Double($0) / 10) }
            )
            steppedRow(
                label: "Measured Width",
                value: $prefs.measuredWidthInCharacters,
                range: 40...100,
                suffix: "characters"
            )
            Toggle("Typewriter scrolling", isOn: $prefs.isTypewriterScrollingEnabled)
                .toggleStyle(.checkbox)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
            if prefs.isTypewriterScrollingEnabled {
                steppedRow(
                    label: "Caret Position",
                    value: Binding(
                        get: { Int(prefs.typewriterCaretFraction * 100) },
                        set: { prefs.typewriterCaretFraction = Double($0) / 100 }
                    ),
                    range: 20...80,
                    suffix: "%"
                )
            }
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(Theme.Color.surface)
    }

    private func steppedRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String,
        displayTransform: (Int) -> String = { "\($0)" }
    ) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Text("\(displayTransform(value.wrappedValue)) \(suffix)")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }
}
