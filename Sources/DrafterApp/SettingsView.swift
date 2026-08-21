import SwiftUI

/// §10's Sync pane. The other panes (General, Editor, Backup, Versioning, Tools) belong
/// to milestones this app hasn't reached yet, so Settings is Sync-only for now rather
/// than shipping stub tabs for features that don't exist.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var tokenDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GitHub Account")
                .font(Theme.Font.heading(15))
                .foregroundStyle(Theme.Color.text)

            if let login = viewModel.connectedLogin {
                statusRow("● Connected as \(login)", color: Theme.Color.accent200)
                Button("Disconnect from GitHub", role: .destructive) {
                    Task { await viewModel.disconnect() }
                }
                .buttonStyle(.nocturneGhost)
            } else {
                statusRow("Not connected", color: Theme.Color.textMuted)
                NocturneField(label: "Personal Access Token", text: $tokenDraft, isSecure: true)
                Button("Test Connection") {
                    Task { await viewModel.testAndSave(token: tokenDraft) }
                }
                .buttonStyle(.nocturneSecondary)
                .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTesting)
            }

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Theme.Color.surface)
        .task { await viewModel.loadStatus() }
    }

    private func statusRow(_ text: String, color: SwiftUI.Color) -> some View {
        Text(text)
            .font(Theme.Font.body(13))
            .foregroundStyle(color)
    }
}
