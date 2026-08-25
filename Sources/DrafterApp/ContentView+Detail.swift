import DrafterCore
import ProjectStore
import SwiftUI

extension ContentView {
    /// The selected binder item, when it's a non-markdown Notes attachment — the one
    /// case `sceneEditor` never loads, so the detail pane needs a different view for it.
    var selectedAttachment: SceneNode? {
        guard let url = selectedSceneURL, !isMarkdownFile(url) else { return nil }
        return projectViewModel.binderTree?.notes.first { $0.url == url }
    }

    func attachmentDetail(_ attachment: SceneNode) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Color.textMuted)
            Text(attachment.displayName)
                .font(Theme.Font.heading(17))
                .foregroundStyle(Theme.Color.text)
            HStack(spacing: 8) {
                Button("Open") { NSWorkspace.shared.open(attachment.url) }
                    .buttonStyle(.nocturnePrimary)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }
                    .buttonStyle(.nocturneSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }

    @ViewBuilder
    var detail: some View {
        if let error = sceneEditor.errorMessage {
            ContentUnavailableView(
                "Couldn't Open Scene", systemImage: "exclamationmark.triangle", description: Text(error)
            )
        } else if let document = sceneEditor.document {
            VStack(spacing: 0) {
                if externalChangeConflictURL == document.url {
                    externalChangeBar(for: document.url)
                }
                SceneTextView(
                    text: sceneBodyBinding,
                    measuredWidthInCharacters: appPreferences.measuredWidthInCharacters,
                    isTypewriterScrollingEnabled: appPreferences.isTypewriterScrollingEnabled,
                    typewriterCaretFraction: appPreferences.typewriterCaretFraction,
                    fontSize: appPreferences.editorFontSize,
                    lineHeightMultiple: appPreferences.editorLineHeightMultiple,
                    jumpRequest: document.url == pendingJumpSceneURL ? pendingJump : nil
                )
            }
        } else if let attachment = selectedAttachment {
            attachmentDetail(attachment)
        } else if let error = projectViewModel.errorMessage {
            ContentUnavailableView(
                "Couldn't Open Project", systemImage: "exclamationmark.triangle", description: Text(error)
            )
        } else if projectViewModel.metadata != nil, let tree = projectViewModel.binderTree, tree.manuscript.isEmpty {
            emptyBinderDetail
        } else if let metadata = projectViewModel.metadata {
            VStack(alignment: .leading, spacing: 8) {
                Text(metadata.title)
                    .font(Theme.Font.heading(28))
                    .foregroundStyle(Theme.Color.text)
                if !metadata.subtitle.isEmpty {
                    Text(metadata.subtitle)
                        .font(Theme.Font.body(17))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                Text(metadata.author)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Color.bg)
        } else {
            NoProjectWelcomeView(
                onNewProject: { isNewProjectSheetPresented = true },
                onAddExisting: presentAddExistingProject,
                onOpenRecent: { url in Task { await projectViewModel.open(root: url) } }
            )
        }
    }

    /// The brand-new-project empty state: Manuscript has no chapters yet, so the
    /// binder's "+ Chapter" affordance is the only way forward — mirrored here as a
    /// centered message + primary button per the handoff.
    var emptyBinderDetail: some View {
        VStack(spacing: 10) {
            Text("This manuscript doesn't have any chapters yet.")
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.Color.textMuted)
            Button("+ Chapter") { isNewChapterSheetPresented = true }
                .buttonStyle(.nocturnePrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
    }

    /// §6.3's "open with unsaved edits" inline bar: never clobbers the buffer
    /// automatically.
    func externalChangeBar(for url: URL) -> some View {
        HStack {
            Text("This scene changed.")
            Spacer()
            Button("Keep Mine") { externalChangeConflictURL = nil }
            Button("Compare") {
                do {
                    let onDisk = try String(contentsOf: url, encoding: .utf8)
                    externalChangeDiffLines = SceneDiff.diff(old: sceneEditor.document?.body ?? "", new: onDisk)
                } catch {
                    // swiftlint:disable:next line_length
                    DrafterLog.app.error("Failed to read \(url.path, privacy: .public) for external-change compare: \(error, privacy: .public)")
                    externalChangeDiffLines = [
                        SceneDiffLine(
                            kind: .unchanged,
                            oldText: "⚠️ Couldn't read the on-disk version of this scene.",
                            newText: "⚠️ Couldn't read the on-disk version of this scene.",
                            oldWords: nil,
                            newWords: nil
                        )
                    ]
                }
                isExternalChangeCompareSheetPresented = true
            }
            Button("Load Theirs") {
                sceneEditor.open(url: url)
                externalChangeConflictURL = nil
            }
        }
        .padding(8)
        .background(.yellow.opacity(0.2))
    }

    var sceneBodyBinding: Binding<String> {
        Binding(
            get: { sceneEditor.document?.body ?? "" },
            set: { sceneEditor.updateBody($0) }
        )
    }
}
