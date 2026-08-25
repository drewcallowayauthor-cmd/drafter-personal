import ProjectStore
import SwiftUI

/// The Git-vs-Local-file mode picker (§5), shared between `NewProjectSheet` and
/// `OnboardingSheet` so the radio rows and description copy stay in sync between the
/// two places a writer can make this choice.
struct VersionControlModePicker: View {
    @Binding var selection: VersionControlMode
    var label = "Version Control"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            NocturneRadioRow(isSelected: selection == .git) {
                selection = .git
            } content: {
                Text("Git + GitHub")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.Color.text)
            }
            NocturneRadioRow(isSelected: selection == .localFile) {
                selection = .localFile
            } content: {
                Text("Local Files + Cloud Folder")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.Color.text)
            }
            Text(description)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var description: String {
        switch selection {
        case .git:
            "Private repo, automatic merging, structured conflict resolution. Needs a GitHub account."
        case .localFile:
            "Snapshots stored next to your manuscript. Put the project in Box, Google Drive, iCloud Drive, " +
                "or OneDrive to sync across machines — works without one too, just without sync."
        }
    }
}
