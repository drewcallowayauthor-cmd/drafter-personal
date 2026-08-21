import AppKit
import ProjectStore
import SwiftUI

/// Collects the fields `Project.create` needs (§5, §4.5) — everything else in
/// `ProjectMetadata` has a sensible default and can be filled in later via Project
/// Settings. The save location defaults to `ProjectViewModel.defaultProjectsDirectory()`
/// but is user-editable here rather than fixed, so a project can be created directly
/// inside e.g. a folder the writer already syncs some other way.
struct NewProjectSheet: View {
    @State private var title = ""
    @State private var author = ""
    @State private var location = ProjectViewModel.defaultProjectsDirectory()
    @State private var versionControl: VersionControlMode = .git
    @State private var manuscriptTemplate: ManuscriptTemplate = .novel
    let onCreate: (
        _ title: String, _ author: String, _ location: URL, _ versionControl: VersionControlMode,
        _ manuscriptTemplate: ManuscriptTemplate
    ) -> Void
    let onCancel: () -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NocturneSheet(title: "New Project", width: 460, onClose: onCancel) {
            NocturneField(label: "Title", text: $title, externalFocus: $isTitleFocused)
            NocturneField(label: "Author", text: $author)
            saveLocationField
            manuscriptTemplatePicker
            versionControlPicker
        } footer: {
            Button("Cancel", action: onCancel)
                .buttonStyle(.nocturneSecondary)
            Button("Create") { onCreate(title, author, location, versionControl, manuscriptTemplate) }
                .buttonStyle(.nocturnePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { isTitleFocused = true }
    }

    private var manuscriptTemplatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manuscript Type")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            ForEach(ManuscriptTemplate.allCases) { template in
                NocturneRadioRow(isSelected: manuscriptTemplate == template) {
                    manuscriptTemplate = template
                } content: {
                    Text(template.rawValue)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.text)
                }
            }
            Text(manuscriptTemplate.description)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveLocationField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Save Location")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            HStack {
                Text(location.path)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Choose…", action: chooseLocation)
                    .buttonStyle(.nocturneSecondary)
            }
        }
    }

    private var versionControlPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version Control")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            NocturneRadioRow(isSelected: versionControl == .git) {
                versionControl = .git
            } content: {
                Text("Git + GitHub")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.Color.text)
            }
            NocturneRadioRow(isSelected: versionControl == .localFile) {
                versionControl = .localFile
            } content: {
                Text("Local Files + Cloud Folder")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.Color.text)
            }
            Text(versionControlDescription)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionControlDescription: String {
        switch versionControl {
        case .git:
            "Private repo, automatic merging, structured conflict resolution. Needs a GitHub account."
        case .localFile:
            "Snapshots stored next to your manuscript. Put the project in Box, Google Drive, iCloud Drive, or OneDrive to sync across machines — works without one too, just without sync."
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = location
        guard panel.runModal() == .OK, let url = panel.url else { return }
        location = url
    }
}
