import AppKit
import SnapshotService
import SwiftUI

/// §12's Version Control pane: the existing GitHub Sync content (§10), plus whichever
/// mode-specific rows apply to the currently open project — read through
/// `OpenProjectHandle`, since Settings is a separate `Scene` with no direct reference to
/// `ContentView`'s `ProjectViewModel`.
struct VersionControlSettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var tokenDraft = ""
    @State private var handle = OpenProjectHandle.shared
    @State private var remoteURL: String?
    @State private var isSnapshotting = false
    @State private var snapshotMessage: String?

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

            Rectangle().fill(Theme.Color.divider).frame(height: 1)

            projectSpecificSection
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(Theme.Color.surface)
        .task { await viewModel.loadStatus() }
        .task(id: handle.workingTreeRoot) { remoteURL = try? await handle.remoteURLDescription() }
    }

    @ViewBuilder
    private var projectSpecificSection: some View {
        switch handle.versionControlMode {
        case .git:
            HStack {
                Text("Remote")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(remoteURL ?? "Not connected")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .localFile:
            localFileSection
        case nil:
            Text("No project open.")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
        }
    }

    private var localFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let root = handle.workingTreeRoot, let provider = SnapshotService.cloudProvider(for: root) {
                statusRow("Syncing via \(provider)", color: Theme.Color.accent200)
            } else {
                statusRow("Not in a synced folder", color: Theme.Color.textMuted)
            }
            HStack {
                Button("Snapshot Now") { Task { await snapshotNow() } }
                    .buttonStyle(.nocturneSecondary)
                    .disabled(isSnapshotting)
                Button("Open History in Finder") { openHistoryInFinder() }
                    .buttonStyle(.nocturneSecondary)
            }
            if let snapshotMessage {
                Text(snapshotMessage)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }
        }
    }

    private func snapshotNow() async {
        isSnapshotting = true
        snapshotMessage = nil
        defer { isSnapshotting = false }
        do {
            try await handle.snapshotNow()
            snapshotMessage = "Snapshot saved."
        } catch {
            snapshotMessage = "Couldn't save a snapshot — \(error.localizedDescription)"
        }
    }

    private func openHistoryInFinder() {
        guard let root = handle.workingTreeRoot else { return }
        NSWorkspace.shared.open(root.appendingPathComponent("History"))
    }

    private func statusRow(_ text: String, color: SwiftUI.Color) -> some View {
        Text(text)
            .font(Theme.Font.body(13))
            .foregroundStyle(color)
    }
}
