import DrafterCore
import GitService
import SwiftUI

extension ContentView {
    /// The 44px in-content toolbar (spec's editor toolbar): status text/pill on the left,
    /// right-aligned action buttons. Native `NSToolbar` items can't be restyled to the
    /// Nocturne outlined-button look, so this replaces what used to be a `.toolbar { }`.
    var editorToolbar: some View {
        HStack(spacing: 10) {
            saveStatus
            if sceneEditor.document != nil {
                Text("·").foregroundStyle(Theme.Color.textMuted)
            }
            syncStatus
            Spacer()
            Button("Typewriter") { appPreferences.isTypewriterScrollingEnabled.toggle() }
                .buttonStyle(.nocturneGhost)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(appPreferences.isTypewriterScrollingEnabled ? Theme.Color.accent : .clear, lineWidth: 1)
                )
            Button("Project Settings…") { isMetadataEditorPresented = true }
                .buttonStyle(.nocturneSecondary)
                .disabled(projectViewModel.metadata == nil)
            Button("Compile…") { isCompileSheetPresented = true }
                .buttonStyle(.nocturnePrimary)
                .disabled(projectViewModel.metadata == nil)
            overflowMenu
            Button(action: { isInspectorPresented.toggle() }, label: {
                Image(systemName: "sidebar.right")
            })
            .buttonStyle(.nocturneIcon)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Theme.Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
        }
    }

    /// Actions the handoff's toolbar spec doesn't call out a slot for — kept reachable
    /// without cluttering the primary button row it does define. New/Add Existing/Open
    /// Project moved to the File menu instead of living here.
    var overflowMenu: some View {
        Menu {
            Button("Generate Front/Back Matter") { generateMissingFrontBackMatter() }
                .disabled(projectViewModel.metadata == nil)
            Button("New Chapter…") { isNewChapterSheetPresented = true }
                .disabled(projectViewModel.metadata == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Color.divider, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    var saveStatus: some View {
        HStack(spacing: 4) {
            if let document = sceneEditor.document {
                Text(document.isDirty ? "Unsaved" : "Saved")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }
            if projectViewModel.autocommitScheduler?.lastCommitFailed == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(.yellow)
                    .help(
                        "The last background commit failed. Your edits are still saved to disk — "
                            + "this will retry on the next change."
                    )
            }
        }
    }

    /// §5.5's glanceable status control: `Synced` · `Syncing…` ·
    /// `Offline — 4 commits pending` · `Conflict — action needed` · `Not synced to GitHub`.
    @ViewBuilder
    var syncStatus: some View {
        if projectViewModel.workingTreeRoot != nil {
            let text = projectViewModel.metadata?.versionControl == .localFile
                ? (projectViewModel.syncStatusMessage ?? "Saved")
                : Self.syncStatusText(for: projectViewModel.syncScheduler?.state)
            if text == "Synced" {
                NocturneTag(text: text, style: .accent)
            } else {
                Text(text)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }
        }
    }

    static func secondsAgoText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) second\(seconds == 1 ? "" : "s") ago" }
        let minutes = seconds / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    static func syncStatusText(for state: SyncState?) -> String {
        guard let state else { return "Not synced to GitHub" }
        switch state {
        case .idle:
            return "Synced"
        case .fetching, .merging, .pushing:
            return "Syncing…"
        case .offline(let pendingCommits):
            return pendingCommits > 0
                ? "Offline — \(pendingCommits) commit\(pendingCommits == 1 ? "" : "s") pending"
                : "Offline"
        case .conflicted:
            return "Conflict — action needed"
        case .authenticationRequired:
            return "Not synced — reconnect in Settings"
        }
    }
}
