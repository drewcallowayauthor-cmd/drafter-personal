import AppKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    func withAlerts(_ content: some View) -> some View {
        withDeleteAndSyncAlerts(withCompiledAndConcurrentEditingAlerts(withRegenerateAndFrontBackMatterAlerts(content)))
    }

    @ViewBuilder
    private func withRegenerateAndFrontBackMatterAlerts(_ content: some View) -> some View {
        content
        .confirmationDialog(
            "Regenerate “\(regenerateConfirmation?.displayName ?? "")” from Template?",
            isPresented: Binding(
                get: { regenerateConfirmation != nil },
                set: { if !$0 { regenerateConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { performRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites any hand edits with the standard template content.")
        }
        .alert(
            "Couldn't Generate Front/Back Matter",
            isPresented: Binding(
                get: { frontBackMatterError != nil },
                set: { if !$0 { frontBackMatterError = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(frontBackMatterError ?? "")
        }
    }

    @ViewBuilder
    private func withCompiledAndConcurrentEditingAlerts(_ content: some View) -> some View {
        content
        .alert(
            "May Be Open Elsewhere",
            isPresented: Binding(
                get: { projectViewModel.concurrentEditingWarning != nil },
                set: { if !$0 { projectViewModel.acknowledgeConcurrentEditingWarning() } }
            )
        ) {
            Button("Cancel", role: .cancel) { Task { await projectViewModel.closeProject() } }
            Button("Continue") { projectViewModel.acknowledgeConcurrentEditingWarning() }
        } message: {
            if let warning = projectViewModel.concurrentEditingWarning {
                Text(
                    "Changes were pushed \(Self.secondsAgoText(warning.secondsAgo)) from \(warning.machineName). "
                        + "Editing in both places at once can create conflicts."
                )
            }
        }
        .alert(
            "Compiled",
            isPresented: Binding(get: { compiledResult != nil }, set: { if !$0 { compiledResult = nil } })
        ) {
            if let compiledResult {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([compiledResult.outputURL])
                }
                Button("Open") { NSWorkspace.shared.open(compiledResult.outputURL) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(compiledResult?.outputURL.lastPathComponent ?? "")
        }
    }

    @ViewBuilder
    private func withDeleteAndSyncAlerts(_ content: some View) -> some View {
        content
        .confirmationDialog(
            "Delete “\(deleteTarget?.displayName ?? "")”?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                Task {
                    if selectedSceneURL == target.url { selectedSceneURL = nil }
                    await projectViewModel.delete(itemAt: target.url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(
                target.isChapter
                    ? "This moves the chapter and all its scenes to the Trash."
                    : "This moves it to the Trash."
            )
        }
        .alert(
            "GitHub Sync",
            isPresented: Binding(
                // Local-file mode reuses `syncStatusMessage` as its persistent toolbar
                // status text (`syncStatus` below), not a one-shot toast — this alert
                // is Git mode's "just connected/failed to connect" notification only.
                get: { projectViewModel.metadata?.versionControl == .git && projectViewModel.syncStatusMessage != nil },
                set: { if !$0 { projectViewModel.acknowledgeSyncStatus() } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(projectViewModel.syncStatusMessage ?? "")
        }
    }
}
