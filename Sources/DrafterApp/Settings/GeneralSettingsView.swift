import AppKit
import SwiftUI

/// §12's General pane: default project location, default author, and reopen-on-launch —
/// none of it needs a live project, so this pane works whether or not one is open.
struct GeneralSettingsView: View {
    @Bindable var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            projectsDirectoryField
            NocturneField(label: "Default Author Name", text: $prefs.defaultAuthorName)
            Toggle("Reopen last project on launch", isOn: $prefs.reopenLastProjectOnLaunch)
                .toggleStyle(.checkbox)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(Theme.Color.surface)
    }

    private var projectsDirectoryField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Default Projects Location")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            HStack {
                Text(prefs.projectsDirectoryPath ?? ProjectViewModel.defaultProjectsDirectory().path)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Choose…", action: chooseDirectory)
                    .buttonStyle(.nocturneSecondary)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: prefs.projectsDirectoryPath ?? ProjectViewModel.defaultProjectsDirectory().path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.projectsDirectoryPath = url.path
    }
}
