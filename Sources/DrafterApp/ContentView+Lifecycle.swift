import DrafterCore
import Foundation
import ProjectStore
import SwiftUI

extension ContentView {
    /// The menu-bar shortcuts added for existing toolbar/context-menu actions
    /// (`DrafterApp.swift`'s "Binder" menu and File-menu additions) — split into its
    /// own chunk for the same reason the file's other `withX` functions are split:
    /// one `.onReceive` chain this long makes the type checker choke well before it's
    /// actually ambiguous.
    @ViewBuilder
    func withShortcutHandlers(_ content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestCompile)) { _ in
            isCompileSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestProjectSettings)) { _ in
            isMetadataEditorPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestNewChapter)) { _ in
            isNewChapterSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestNewScene)) { _ in
            newSceneChapterURL = chapterURLForNewScene
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestNewNote)) { _ in
            isNewNoteSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestDeleteSelection)) { _ in
            requestDeleteSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestToggleInspector)) { _ in
            isInspectorPresented.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestToggleTypewriterScrolling)) { _ in
            appPreferences.isTypewriterScrollingEnabled.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestProjectFindReplace)) { _ in
            isProjectFindReplacePresented = true
        }
    }

    /// A find-in-project result was clicked: select its scene (opening it in the editor
    /// via the `selectedSceneURL` `onChange` below) and hand `SceneTextView` the range to
    /// select once that open completes, then dismiss the sheet so the editor is visible.
    func jump(to match: ProjectSearchMatch) {
        isProjectFindReplacePresented = false
        pendingJumpSceneURL = match.sceneURL
        pendingJump = SceneTextJumpRequest(range: match.range)
        expandedChapterURLs.insert(match.sceneURL.deletingLastPathComponent())
        selectedSceneURL = match.sceneURL
    }

    /// Split into several smaller `withX` chunks — same "the type checker chokes on
    /// one huge modifier chain" reason as `withShortcutHandlers`/`withAlerts`/
    /// `withProjectSheets` above, and it also keeps each chunk under SwiftLint's
    /// function-body-length limit.
    func withLifecycleHandlers(_ content: some View) -> some View {
        withLaunchHandlers(withProjectStateHandlers(withNotificationHandlers(withDocumentHandlers(content))))
    }

    private func withDocumentHandlers(_ content: some View) -> some View {
        content
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await projectViewModel.open(root: url) }
            }
        }
        .onChange(of: selectedSceneURL) { _, newURL in
            // Deferred to the next run-loop tick: this fires from inside AppKit's own
            // NSTableView delegate callback for the selection change, and opening/
            // closing the scene mutates @Observable state synchronously — which
            // otherwise triggers "reentrant operation in NSTableView delegate" (a
            // warning today, an assert in a future macOS per the console message).
            DispatchQueue.main.async {
                // Chapter folder rows are implicitly selectable too (ChapterNode is
                // Identifiable, so List infers a tag from its id even without an
                // explicit .tag()) — only actually open something for a real scene.
                // A Notes attachment (a non-markdown reference document) is
                // selectable but isn't text the scene editor can load — it gets its
                // own detail pane (`selectedAttachment`/`attachmentDetail`) instead.
                if let newURL, isOpenableScene(newURL), isMarkdownFile(newURL) {
                    sceneEditor.open(url: newURL)
                } else {
                    sceneEditor.close()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // "App loses focus" (§8.3 point 9, §5.4) — flush the pending disk write
            // immediately rather than waiting out its debounce, then commit immediately
            // too rather than waiting out the separate 90s commit debounce.
            if newPhase != .active {
                sceneEditor.saveNow()
                Task { await projectViewModel.autocommitScheduler?.flush(trigger: .focusLost) }
            } else {
                // "Window regains focus" (§5.5, §6.4).
                projectViewModel.syncScheduler?.syncOnFocusRegained()
                Task { await projectViewModel.checkConcurrentEditing() }
            }
        }
    }

    private func withNotificationHandlers(_ content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestCheckpoint)) { _ in
            handleRequestCheckpoint()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterCredentialsUpdated)) { _ in
            Task { await projectViewModel.refreshCredentialsAndResync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestNewProject)) { _ in
            isNewProjectSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestAddExistingProject)) { _ in
            presentAddExistingProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestOpenProject)) { _ in
            isImporterPresented = true
        }
    }

    private func withProjectStateHandlers(_ content: some View) -> some View {
        content
        .onChange(of: projectViewModel.workingTreeRoot) { _, newRoot in
            historyViewModel = projectViewModel.versioningSource.map { HistoryViewModel(source: $0) }
            targetsViewModel.resetSession()
            conflictedCopyViewModel.clear()
            if let newRoot, projectViewModel.metadata?.versionControl == .localFile {
                conflictedCopyViewModel.scan(workingTree: newRoot)
            }
            // `binderTree` is populated before `workingTreeRoot` in `ProjectViewModel`
            // (both set synchronously in the same open call), so it already reflects
            // the newly opened project here.
            expandedChapterURLs = Set(
                (projectViewModel.binderTree?.manuscript ?? []).filter { !$0.isLooseFile }.map(\.url)
            )
        }
        .onChange(of: projectViewModel.binderTree) { _, newTree in
            if let newTree {
                targetsViewModel.recalculate(binderTree: newTree)
            }
        }
        .onChange(of: historyViewModel?.restoredFileURL) { _, newValue in
            guard newValue != nil else { return }
            Task {
                await projectViewModel.refresh()
                historyViewModel?.clearRestoredFileURL()
            }
        }
        .modifier(VersioningPreferencesSync(
            appPreferences: appPreferences,
            sceneEditor: sceneEditor,
            projectViewModel: projectViewModel
        ))
    }

    private func withLaunchHandlers(_ content: some View) -> some View {
        content
        .task {
            await setUpHandlersAndOpenDebugProject()
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    func handleRequestCheckpoint() {
        sceneEditor.saveNow()
        Task { await projectViewModel.autocommitScheduler?.flush(trigger: .checkpoint(label: nil)) }
    }

    func setUpHandlersAndOpenDebugProject() async {
        // Reads projectViewModel.autocommitScheduler dynamically on each save rather
        // than capturing today's value, since it's created after the project (and its
        // repo) finishes opening.
        sceneEditor.onSaved = { wordDelta in
            projectViewModel.autocommitScheduler?.recordActivity(wordDelta: wordDelta)
            targetsViewModel.recordSessionActivity(wordDelta: wordDelta)
        }
        // §6.3's three reload rules. A file not open in the editor is covered by the
        // `refresh()` alone (it just needs the binder to reflect it); the other two
        // branches are about whatever scene the editor currently has open, read fresh
        // each time onExternalChange fires rather than captured, since which scene is
        // open changes independently of the project.
        projectViewModel.onExternalChange = { changedURLs in
            Task { await handleExternalChange(changedURLs: changedURLs) }
        }
        await openDebugProjectIfRequested()
        await reopenLastProjectIfRequested()
    }

    /// General pane's "reopen last project on launch" (§12): only fires when nothing
    /// else already opened a project this launch (debug override, or a project the OS
    /// asks us to open) and the writer has opted in.
    /// "Add Existing" (§5.9) branches on the last-picked version-control mode
    /// (`NewProjectSheet.defaultVersionControlMode()`'s same source): Git mode clones
    /// from the account's GitHub repos, since a local folder alone isn't "existing" in
    /// any useful sense without a remote — Local-file mode has no such registry, so it
    /// just browses for the folder directly, reusing the same importer "Open
    /// Project…" already uses.
    func presentAddExistingProject() {
        switch NewProjectSheet.defaultVersionControlMode() {
        case .git:
            isCloneProjectSheetPresented = true
        case .localFile:
            isImporterPresented = true
        }
    }

    func reopenLastProjectIfRequested() async {
        guard projectViewModel.metadata == nil else { return }
        guard AppPreferences.shared.reopenLastProjectOnLaunch else { return }
        guard let path = AppPreferences.shared.lastOpenedProjectPath else { return }
        await projectViewModel.openSilently(root: URL(fileURLWithPath: path))
    }

    func handleExternalChange(changedURLs: Set<URL>) async {
        await projectViewModel.refresh()
        // §7.5: a cloud client's own conflict-copy file is exactly the kind of change
        // that arrives via FSEvents rather than through the app's own writes.
        if let workingTreeRoot = projectViewModel.workingTreeRoot,
           projectViewModel.metadata?.versionControl == .localFile {
            conflictedCopyViewModel.scan(workingTree: workingTreeRoot)
        }
        guard let document = sceneEditor.document else { return }
        // Only the open scene's *own* file matters here — an unrelated write
        // elsewhere in the tree (a new chapter being created, front/back matter
        // regenerating, another scene autosaving) must never pop this scene's reload
        // prompt just because something in the project changed.
        guard changedURLs.contains(document.url.resolvingSymlinksInPath()) else { return }
        if document.isDirty {
            externalChangeConflictURL = document.url
        } else {
            sceneEditor.open(url: document.url)
        }
    }

    /// Dev-only convenience for visually verifying UI changes without clicking through
    /// the picker: `DRAFTER_DEBUG_PROJECT_PATH=/path/to/project swift run`.
    func openDebugProjectIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["DRAFTER_DEBUG_PROJECT_PATH"] else { return }
        await projectViewModel.open(root: URL(fileURLWithPath: path))
        if let firstScene = projectViewModel.binderTree?.manuscript.first(where: { !$0.isLooseFile })?.scenes.first {
            selectedSceneURL = firstScene.url
        }
    }
}
