import AppKit
import SwiftUI

/// §12's Tools pane: one row per external binary Drafter shells out to, with an override
/// field that feeds `BinaryResolver` ahead of its usual candidate-directory/PATH search.
struct ToolsSettingsView: View {
    @State private var viewModel = ToolsSettingsViewModel()
    @Bindable private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.statuses) { status in
                toolRow(status)
            }
        }
        .padding(18)
        .frame(width: 500, alignment: .leading)
        .background(Theme.Color.surface)
        .onAppear { viewModel.refresh() }
        .onChange(of: prefs.gitPathOverride) { _, _ in viewModel.refresh() }
        .onChange(of: prefs.pandocPathOverride) { _, _ in viewModel.refresh() }
        .onChange(of: prefs.typstPathOverride) { _, _ in viewModel.refresh() }
        .onChange(of: prefs.epubcheckPathOverride) { _, _ in viewModel.refresh() }
    }

    private func toolRow(_ status: ToolsSettingsViewModel.ToolStatus) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(status.displayName)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(status.resolvedPath ?? "Not found")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(status.resolvedPath == nil ? .red : Theme.Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack {
                NocturneField(label: "Override", text: overrideBinding(for: status.id))
                Button("Choose…") { chooseOverride(for: status.id) }
                    .buttonStyle(.nocturneSecondary)
            }
        }
        .padding(.bottom, 6)
    }

    private func overrideBinding(for id: String) -> Binding<String> {
        Binding(
            get: { override(for: id) ?? "" },
            set: { setOverride(for: id, to: $0.isEmpty ? nil : $0) }
        )
    }

    private func override(for id: String) -> String? {
        switch id {
        case "git": prefs.gitPathOverride
        case "pandoc": prefs.pandocPathOverride
        case "typst": prefs.typstPathOverride
        case "epubcheck": prefs.epubcheckPathOverride
        default: nil
        }
    }

    private func setOverride(for id: String, to value: String?) {
        switch id {
        case "git": prefs.gitPathOverride = value
        case "pandoc": prefs.pandocPathOverride = value
        case "typst": prefs.typstPathOverride = value
        case "epubcheck": prefs.epubcheckPathOverride = value
        default: break
        }
    }

    private func chooseOverride(for id: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setOverride(for: id, to: url.path)
    }
}
