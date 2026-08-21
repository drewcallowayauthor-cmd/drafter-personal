import AppKit
import DrafterCore
import GitService
import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

/// The Binder/Editor/Inspector layout (§8.1). Inspector currently holds History (§5.8);
/// Scene and Targets sections are later additions to the same pane.
struct ContentView: View {
    @State private var projectViewModel = ProjectViewModel()
    @State private var sceneEditor = SceneEditorViewModel(autosaveDelay: .seconds(AppPreferences.shared.autosaveDelaySeconds))
    @State private var historyViewModel: HistoryViewModel?
    @State private var conflictedCopyViewModel = ConflictedCopyViewModel()
    @State private var targetsViewModel = TargetsViewModel()
    @State private var isImporterPresented = false
    @State private var isInspectorPresented = true
    @State private var selectedSceneURL: URL?
    @State private var appPreferences = AppPreferences.shared
    @State private var regenerateConfirmation: (template: FrontBackMatterTemplate, displayName: String)?
    @State private var frontBackMatterError: String?
    @State private var isMetadataEditorPresented = false
    @State private var isCompileSheetPresented = false
    @State private var compiledResult: CompileOutcome?
    @State private var isNewProjectSheetPresented = false
    @State private var isOnboardingSheetPresented = !AppPreferences.shared.hasCompletedOnboarding
    @State private var isCloneProjectSheetPresented = false
    @State private var isConflictSheetPresented = false
    @State private var isNewChapterSheetPresented = false
    /// Non-nil while the "New Scene…" prompt is up, naming which chapter it's for.
    @State private var newSceneChapterURL: URL?
    /// Non-nil while the "New Note…" prompt is up.
    @State private var isNewNoteSheetPresented = false
    /// Which Manuscript chapters' `DisclosureGroup`s are expanded — reset to "all
    /// expanded" whenever a project opens (§8.1: the binder should show its contents
    /// immediately, not require expanding every chapter by hand), then left to the
    /// user's own expand/collapse choices for the rest of the session.
    @State private var expandedChapterURLs: Set<URL> = []
    /// Non-nil while the binder's "Rename…" prompt is up.
    @State private var renameTarget: BinderRenameTarget?
    /// Non-nil while the binder's delete confirmation is up.
    @State private var deleteTarget: BinderDeleteTarget?
    /// §6.3's "open with unsaved edits" rule: set to the scene's URL when an external
    /// change (a git integration) touched the file the editor has dirty, so the inline
    /// bar shows only for that scene, not a stale one after switching away.
    @State private var externalChangeConflictURL: URL?
    @State private var isExternalChangeCompareSheetPresented = false
    @State private var externalChangeDiffLines: [SceneDiffLine] = []
    @State private var toastCenter = ToastCenter()
    @State private var isProjectFindReplacePresented = false
    /// §8.3 point 8's "jumps to scene and offset" — set alongside `selectedSceneURL`
    /// when a find-in-project result is clicked; `pendingJumpSceneURL` guards against
    /// handing a stale range to whichever scene happens to be open once the selection
    /// change (and its dispatch-async'd `sceneEditor.open`, see `onChange` below) lands.
    @State private var pendingJump: SceneTextJumpRequest?
    @State private var pendingJumpSceneURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    // Split into several grouped chunks rather than one long modifier chain: a chain
    // this long makes the type checker choke ("unable to type-check this expression
    // in reasonable time") well before it's actually ambiguous — each `withX` below is
    // small enough to check on its own.
    var body: some View {
        withShortcutHandlers(withLifecycleHandlers(withProjectSheets(withAlerts(mainLayout))))
    }

    private var mainLayout: some View {
        NavigationSplitView {
            binderList
        } detail: {
            VStack(spacing: 0) {
                editorToolbar
                if !conflictedCopyViewModel.matches.isEmpty {
                    ConflictedCopyBanner(viewModel: conflictedCopyViewModel)
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.bg)
            .nocturneToastOverlay(center: toastCenter)
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspector
        }
        .tint(Theme.Color.accent)
    }

    @ViewBuilder
    private func withAlerts(_ content: some View) -> some View {
        content
        .confirmationDialog(
            "Regenerate “\(regenerateConfirmation?.displayName ?? "")” from Template?",
            isPresented: Binding(get: { regenerateConfirmation != nil }, set: { if !$0 { regenerateConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { performRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites any hand edits with the standard template content.")
        }
        .alert("Couldn't Generate Front/Back Matter", isPresented: Binding(get: { frontBackMatterError != nil }, set: { if !$0 { frontBackMatterError = nil } })) {
            Button("OK") {}
        } message: {
            Text(frontBackMatterError ?? "")
        }
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

    @ViewBuilder
    private func withProjectSheets(_ content: some View) -> some View {
        content
        .sheet(isPresented: $isOnboardingSheetPresented) {
            OnboardingSheet(onFinish: { isOnboardingSheetPresented = false })
                .nocturneSheetPresentation()
        }
        .sheet(isPresented: $isMetadataEditorPresented) {
            if let metadata = projectViewModel.metadata {
                ProjectMetadataEditor(
                    metadata: metadata,
                    snapshotService: projectViewModel.snapshotService,
                    workingTree: projectViewModel.workingTreeRoot,
                    isGitHubConnected: projectViewModel.syncScheduler != nil,
                    onConnectToGitHub: { Task { await projectViewModel.connectToGitHub() } },
                    onSnapshotNow: {
                        Task { await projectViewModel.autocommitScheduler?.flush(trigger: .checkpoint(label: "manual snapshot")) }
                    },
                    onSave: { updated in
                        Task { await projectViewModel.save(metadata: updated) }
                        isMetadataEditorPresented = false
                    },
                    onCancel: { isMetadataEditorPresented = false }
                )
                .nocturneSheetPresentation()
            }
        }
        .onChange(of: projectViewModel.syncScheduler?.state) { _, newState in
            if case .conflicted = newState {
                isConflictSheetPresented = true
            }
        }
        .sheet(isPresented: $isConflictSheetPresented) {
            if case .conflicted(let paths) = projectViewModel.syncScheduler?.state,
                let gitService = projectViewModel.gitService, let workingTree = projectViewModel.workingTreeRoot
            {
                ConflictSheet(
                    paths: paths,
                    gitService: gitService,
                    workingTree: workingTree,
                    machineName: RepositoryCoordinator.defaultMachineName(),
                    onResolved: {
                        isConflictSheetPresented = false
                        Task {
                            await projectViewModel.syncScheduler?.resolveConflict()
                            await projectViewModel.refresh()
                        }
                    },
                    onCancel: { isConflictSheetPresented = false }
                )
                .nocturneSheetPresentation()
            }
        }
        .sheet(isPresented: $isNewChapterSheetPresented) {
            TextPromptSheet(
                title: "New Chapter",
                fieldLabel: "Chapter Title",
                confirmLabel: "Create",
                onSubmit: { title in
                    isNewChapterSheetPresented = false
                    Task {
                        if let sceneURL = await projectViewModel.createChapter(title: title) {
                            selectedSceneURL = sceneURL
                            expandedChapterURLs.insert(sceneURL.deletingLastPathComponent())
                        }
                    }
                },
                onCancel: { isNewChapterSheetPresented = false }
            )
            .nocturneSheetPresentation()
        }
        .sheet(
            isPresented: Binding(
                get: { newSceneChapterURL != nil },
                set: { if !$0 { newSceneChapterURL = nil } }
            )
        ) {
            if let chapterURL = newSceneChapterURL {
                TextPromptSheet(
                    title: "New Scene",
                    fieldLabel: "Scene Title",
                    confirmLabel: "Create",
                    onSubmit: { title in
                        newSceneChapterURL = nil
                        Task {
                            if let sceneURL = await projectViewModel.createScene(title: title, in: chapterURL) {
                                selectedSceneURL = sceneURL
                            }
                        }
                    },
                    onCancel: { newSceneChapterURL = nil }
                )
                .nocturneSheetPresentation()
            }
        }
        .sheet(isPresented: $isNewNoteSheetPresented) {
            TextPromptSheet(
                title: "New Note",
                fieldLabel: "Note Title",
                confirmLabel: "Create",
                onSubmit: { title in
                    isNewNoteSheetPresented = false
                    guard let notesDirectoryURL else { return }
                    Task {
                        if let sceneURL = await projectViewModel.createScene(title: title, in: notesDirectoryURL) {
                            selectedSceneURL = sceneURL
                        }
                    }
                },
                onCancel: { isNewNoteSheetPresented = false }
            )
            .nocturneSheetPresentation()
        }
        .sheet(item: $renameTarget) { target in
            TextPromptSheet(
                title: "Rename",
                fieldLabel: "Title",
                confirmLabel: "Rename",
                initialText: target.currentTitle,
                onSubmit: { newTitle in
                    renameTarget = nil
                    Task {
                        let renamedURL = await projectViewModel.rename(itemAt: target.url, to: newTitle)
                        if let renamedURL, selectedSceneURL == target.url {
                            selectedSceneURL = renamedURL
                        }
                    }
                },
                onCancel: { renameTarget = nil }
            )
            .nocturneSheetPresentation()
        }
        .sheet(isPresented: $isNewProjectSheetPresented) {
            NewProjectSheet(
                onCreate: { title, author, location, versionControl, manuscriptTemplate in
                    isNewProjectSheetPresented = false
                    Task {
                        await projectViewModel.createNewProject(
                            title: title,
                            author: author,
                            location: location,
                            versionControl: versionControl,
                            manuscriptTemplate: manuscriptTemplate
                        )
                        if projectViewModel.errorMessage == nil {
                            // Scaffold the standard front/back matter files immediately
                            // rather than leaving a brand-new project with none —
                            // "Regenerate from Template" (binder context menu) remains
                            // how to refresh any of them later.
                            generateMissingFrontBackMatter()
                            toastCenter.show("Project created")
                        }
                    }
                },
                onCancel: { isNewProjectSheetPresented = false }
            )
            .nocturneSheetPresentation()
        }
        .sheet(isPresented: $isCloneProjectSheetPresented) {
            GitHubRepoPickerSheet(
                onSelect: { repository in
                    isCloneProjectSheetPresented = false
                    Task { await projectViewModel.cloneProject(repository) }
                },
                onCancel: { isCloneProjectSheetPresented = false }
            )
            .nocturneSheetPresentation()
        }
        .sheet(isPresented: $isCompileSheetPresented) {
            if let metadata = projectViewModel.metadata, let binderTree = projectViewModel.binderTree,
                let workingTree = projectViewModel.workingTreeRoot
            {
                CompileSheet(
                    metadata: metadata,
                    binderTree: binderTree,
                    workingTree: workingTree,
                    onCancel: { isCompileSheetPresented = false },
                    onCompiled: { result in compiledResult = result }
                )
                .nocturneSheetPresentation()
            }
        }
        .sheet(isPresented: $isProjectFindReplacePresented) {
            ProjectFindReplaceSheet(
                performSearch: { options in await projectViewModel.search(options: options) },
                performReplace: { matches, replacement in await projectViewModel.replace(matches: matches, replacement: replacement) },
                flushOpenScene: { sceneEditor.saveNow() },
                reloadIfOpen: { rewrittenURLs in
                    if let selectedSceneURL, rewrittenURLs.contains(selectedSceneURL) {
                        sceneEditor.open(url: selectedSceneURL)
                    }
                },
                onCancel: { isProjectFindReplacePresented = false },
                onJump: { match in jump(to: match) }
            )
            .nocturneSheetPresentation()
        }
        .sheet(isPresented: $isExternalChangeCompareSheetPresented) {
            DiffView(lines: externalChangeDiffLines, oldLabel: "Mine", newLabel: "On Disk")
                .nocturneSheetPresentation()
        }
    }

    /// The menu-bar shortcuts added for existing toolbar/context-menu actions
    /// (`DrafterApp.swift`'s "Binder" menu and File-menu additions) — split into its
    /// own chunk for the same reason the file's other `withX` functions are split:
    /// one `.onReceive` chain this long makes the type checker choke well before it's
    /// actually ambiguous.
    @ViewBuilder
    private func withShortcutHandlers(_ content: some View) -> some View {
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
    private func jump(to match: ProjectSearchMatch) {
        isProjectFindReplacePresented = false
        pendingJumpSceneURL = match.sceneURL
        pendingJump = SceneTextJumpRequest(range: match.range)
        expandedChapterURLs.insert(match.sceneURL.deletingLastPathComponent())
        selectedSceneURL = match.sceneURL
    }

    private func withLifecycleHandlers(_ content: some View) -> some View {
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
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestCheckpoint)) { _ in
            sceneEditor.saveNow()
            Task { await projectViewModel.autocommitScheduler?.flush(trigger: .checkpoint(label: nil)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterCredentialsUpdated)) { _ in
            Task { await projectViewModel.refreshCredentialsAndResync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestNewProject)) { _ in
            isNewProjectSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestAddExistingProject)) { _ in
            isCloneProjectSheetPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestOpenProject)) { _ in
            isImporterPresented = true
        }
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
        .task {
            await setUpHandlersAndOpenDebugProject()
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    /// The 44px in-content toolbar (spec's editor toolbar): status text/pill on the left,
    /// right-aligned action buttons. Native `NSToolbar` items can't be restyled to the
    /// Nocturne outlined-button look, so this replaces what used to be a `.toolbar { }`.
    private var editorToolbar: some View {
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
            Button(action: { isInspectorPresented.toggle() }) {
                Image(systemName: "sidebar.right")
            }
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
    private var overflowMenu: some View {
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
    private var saveStatus: some View {
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
                    .help("The last background commit failed. Your edits are still saved to disk — this will retry on the next change.")
            }
        }
    }

    /// §5.5's glanceable status control: `Synced` · `Syncing…` ·
    /// `Offline — 4 commits pending` · `Conflict — action needed` · `Not synced to GitHub`.
    @ViewBuilder
    private var syncStatus: some View {
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

    private static func secondsAgoText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) second\(seconds == 1 ? "" : "s") ago" }
        let minutes = seconds / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    private static func syncStatusText(for state: SyncState?) -> String {
        guard let state else { return "Not synced to GitHub" }
        switch state {
        case .idle:
            return "Synced"
        case .fetching, .merging, .pushing:
            return "Syncing…"
        case .offline(let pendingCommits):
            return pendingCommits > 0 ? "Offline — \(pendingCommits) commit\(pendingCommits == 1 ? "" : "s") pending" : "Offline"
        case .conflicted:
            return "Conflict — action needed"
        case .authenticationRequired:
            return "Not synced — reconnect in Settings"
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if projectViewModel.metadata != nil {
            VStack(spacing: 0) {
                TargetsPanel(
                    totals: targetsViewModel.totals,
                    targetWords: projectViewModel.metadata?.target.words ?? 0,
                    sessionWords: targetsViewModel.sessionWords
                )
                Rectangle().fill(Theme.Color.divider).frame(height: 1)
                historySection
            }
            .background(Theme.Color.surface)
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "chart.bar",
                description: Text("Open a project to see word count targets and history.")
            )
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let historyViewModel, let sceneURL = selectedSceneURL, isOpenableScene(sceneURL),
            let workingTree = projectViewModel.workingTreeRoot
        {
            HistoryPanel(
                history: historyViewModel,
                sceneURL: sceneURL,
                workingTree: workingTree,
                currentBody: sceneEditor.document?.body ?? ""
            )
        } else {
            ContentUnavailableView(
                "No Scene Selected",
                systemImage: "clock",
                description: Text("Select a scene to see its history.")
            )
        }
    }

    @ViewBuilder
    private var binderList: some View {
        if let tree = projectViewModel.binderTree {
            List(selection: $selectedSceneURL) {
                Section("Manuscript") {
                    ForEach(tree.manuscript) { chapter in
                        if chapter.isLooseFile {
                            Text(chapter.displayName).tag(chapter.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: chapter.url))
                                .contextMenu {
                                    binderRenameDeleteMenu(url: chapter.url, currentTitle: chapter.displayName, isChapter: true)
                                }
                        } else {
                            DisclosureGroup(isExpanded: isChapterExpandedBinding(chapter.url)) {
                                ForEach(chapter.scenes) { scene in
                                    Text(scene.displayName).tag(scene.url)
                                        .foregroundStyle(Theme.Color.text)
                                        .listRowBackground(rowBackground(for: scene.url))
                                        .contextMenu { sceneContextMenu(scene: scene, currentChapter: chapter) }
                                        .draggable(scene.url.absoluteString)
                                        .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                                            handleSceneDrop(items, into: chapter, before: scene)
                                        }
                                }
                            } label: {
                                Text(chapter.displayName)
                            }
                            .foregroundStyle(Theme.Color.text)
                            .contextMenu {
                                Button("New Scene…") { newSceneChapterURL = chapter.url }
                                Divider()
                                binderRenameDeleteMenu(url: chapter.url, currentTitle: chapter.displayName, isChapter: true)
                            }
                        }
                    }
                    .onMove(perform: moveChapters)
                    Button("+ Chapter") { isNewChapterSheetPresented = true }
                        .buttonStyle(.nocturneGhost)
                        .frame(height: 24)
                        .listRowBackground(SwiftUI.Color.clear)
                }
                if !tree.frontMatter.isEmpty || coverImageURL != nil {
                    Section("Front Matter") {
                        coverImageRow
                        ForEach(tree.frontMatter) { scene in
                            Text(scene.displayName).tag(scene.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: scene.url))
                                .contextMenu {
                                    regenerateMenuItem(for: scene)
                                    binderRenameDeleteMenu(url: scene.url, currentTitle: scene.displayName, isChapter: false)
                                }
                        }
                        .onMove { source, destination in moveFlatSection(tree.frontMatter, from: source, to: destination) }
                    }
                    // Dropping an image file here sets it as the book cover (§4.5's
                    // `compile.coverImage`) rather than adding a binder row — the cover
                    // lives in `Resources/`, not as a Front Matter scene.
                    .dropDestination(for: URL.self) { urls, _ in handleCoverImageDrop(urls) }
                }
                if !tree.backMatter.isEmpty {
                    Section("Back Matter") {
                        ForEach(tree.backMatter) { scene in
                            Text(scene.displayName).tag(scene.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: scene.url))
                                .contextMenu {
                                    regenerateMenuItem(for: scene)
                                    binderRenameDeleteMenu(url: scene.url, currentTitle: scene.displayName, isChapter: false)
                                }
                        }
                        .onMove { source, destination in moveFlatSection(tree.backMatter, from: source, to: destination) }
                    }
                }
                // Always visible (unlike Front/Back Matter, which only appear once
                // seeded) so "+ Note" and the Finder-drop target are always reachable —
                // Notes has no template scaffolding to seed it at project creation.
                Section("Notes") {
                    ForEach(tree.notes) { note in
                        noteRow(note)
                    }
                    .onMove { source, destination in moveFlatSection(tree.notes, from: source, to: destination) }
                    Button("+ Note") { isNewNoteSheetPresented = true }
                        .buttonStyle(.nocturneGhost)
                        .frame(height: 24)
                        .listRowBackground(SwiftUI.Color.clear)
                }
                // Reference documents (PDFs, images, anything) dropped from Finder are
                // copied in as-is, keeping their own extension — unlike scenes, which
                // are always created as `.md`.
                .dropDestination(for: URL.self) { urls, _ in handleNotesDrop(urls) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bg)
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "book.closed",
                description: Text("Open a project folder to browse its manuscript.")
            )
        }
    }

    /// The accent-800 selected-row background the handoff specifies — `List` selection's
    /// system highlight is overridden per-row rather than relying on the platform default.
    private func rowBackground(for url: URL) -> SwiftUI.Color {
        selectedSceneURL == url ? Theme.Color.accent800 : .clear
    }

    /// The selected binder item, when it's a non-markdown Notes attachment — the one
    /// case `sceneEditor` never loads, so the detail pane needs a different view for it.
    private var selectedAttachment: SceneNode? {
        guard let url = selectedSceneURL, !isMarkdownFile(url) else { return nil }
        return projectViewModel.binderTree?.notes.first { $0.url == url }
    }

    private func attachmentDetail(_ attachment: SceneNode) -> some View {
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
    private var detail: some View {
        if let error = sceneEditor.errorMessage {
            ContentUnavailableView("Couldn't Open Scene", systemImage: "exclamationmark.triangle", description: Text(error))
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
            ContentUnavailableView("Couldn't Open Project", systemImage: "exclamationmark.triangle", description: Text(error))
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
                onAddExisting: { isCloneProjectSheetPresented = true },
                onOpenRecent: { url in Task { await projectViewModel.open(root: url) } }
            )
        }
    }

    /// The brand-new-project empty state: Manuscript has no chapters yet, so the
    /// binder's "+ Chapter" affordance is the only way forward — mirrored here as a
    /// centered message + primary button per the handoff.
    private var emptyBinderDetail: some View {
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

    private func setUpHandlersAndOpenDebugProject() async {
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
        projectViewModel.onExternalChange = { changedURLs in Task { await handleExternalChange(changedURLs: changedURLs) } }
        await openDebugProjectIfRequested()
        await reopenLastProjectIfRequested()
    }

    /// General pane's "reopen last project on launch" (§12): only fires when nothing
    /// else already opened a project this launch (debug override, or a project the OS
    /// asks us to open) and the writer has opted in.
    private func reopenLastProjectIfRequested() async {
        guard projectViewModel.metadata == nil else { return }
        guard AppPreferences.shared.reopenLastProjectOnLaunch else { return }
        guard let path = AppPreferences.shared.lastOpenedProjectPath else { return }
        await projectViewModel.openSilently(root: URL(fileURLWithPath: path))
    }

    private func handleExternalChange(changedURLs: Set<URL>) async {
        await projectViewModel.refresh()
        // §7.5: a cloud client's own conflict-copy file is exactly the kind of change
        // that arrives via FSEvents rather than through the app's own writes.
        if let workingTreeRoot = projectViewModel.workingTreeRoot, projectViewModel.metadata?.versionControl == .localFile {
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
    private func openDebugProjectIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["DRAFTER_DEBUG_PROJECT_PATH"] else { return }
        await projectViewModel.open(root: URL(fileURLWithPath: path))
        if let firstScene = projectViewModel.binderTree?.manuscript.first(where: { !$0.isLooseFile })?.scenes.first {
            selectedSceneURL = firstScene.url
        }
    }

    /// §6.3's "open with unsaved edits" inline bar: never clobbers the buffer
    /// automatically.
    private func externalChangeBar(for url: URL) -> some View {
        HStack {
            Text("This scene changed.")
            Spacer()
            Button("Keep Mine") { externalChangeConflictURL = nil }
            Button("Compare") {
                do {
                    let onDisk = try String(contentsOf: url, encoding: .utf8)
                    externalChangeDiffLines = SceneDiff.diff(old: sceneEditor.document?.body ?? "", new: onDisk)
                } catch {
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

    /// Shared "Rename…"/"Delete…" pair for every binder row (§8.2).
    @ViewBuilder
    private func binderRenameDeleteMenu(url: URL, currentTitle: String, isChapter: Bool) -> some View {
        Button("Rename…") { renameTarget = BinderRenameTarget(url: url, currentTitle: currentTitle) }
        Button(isChapter ? "Delete Chapter…" : "Delete…", role: .destructive) {
            deleteTarget = BinderDeleteTarget(url: url, displayName: currentTitle, isChapter: isChapter)
        }
    }

    private func isChapterExpandedBinding(_ chapterURL: URL) -> Binding<Bool> {
        Binding(
            get: { expandedChapterURLs.contains(chapterURL) },
            set: { isExpanded in
                if isExpanded { expandedChapterURLs.insert(chapterURL) } else { expandedChapterURLs.remove(chapterURL) }
            }
        )
    }

    /// Drag-to-reorder for `Section("Manuscript")`'s chapters.
    private func moveChapters(from source: IndexSet, to destination: Int) {
        guard let tree = projectViewModel.binderTree else { return }
        var urls = tree.manuscript.map(\.url)
        urls.move(fromOffsets: source, toOffset: destination)
        Task { await projectViewModel.reorder(orderedURLs: urls) }
    }

    /// A scene's context menu: rename/delete, plus "Move to Chapter" — a
    /// non-drag fallback for moving a scene into another chapter (§8.2), since
    /// drag-and-drop alone can't reach a collapsed or off-screen chapter.
    @ViewBuilder
    private func sceneContextMenu(scene: SceneNode, currentChapter: ChapterNode) -> some View {
        binderRenameDeleteMenu(url: scene.url, currentTitle: scene.displayName, isChapter: false)
        if let tree = projectViewModel.binderTree {
            let otherChapters = tree.manuscript.filter { !$0.isLooseFile && $0.url != currentChapter.url }
            if !otherChapters.isEmpty {
                Menu("Move to Chapter") {
                    ForEach(otherChapters) { target in
                        Button(target.displayName) {
                            Task { await projectViewModel.moveScene(scene.url, toChapterDirectory: target.url, before: nil) }
                        }
                    }
                }
            }
        }
    }

    /// Drop target for a scene row (§8.2's drag-to-reorder/cross-chapter move):
    /// drops land immediately before the row dropped on, in that row's chapter —
    /// which may be a different chapter than the dragged scene's current one.
    private func handleSceneDrop(_ items: [String], into chapter: ChapterNode, before targetScene: SceneNode?) -> Bool {
        guard !chapter.isLooseFile, let urlString = items.first, let sourceURL = URL(string: urlString) else { return false }
        Task { await projectViewModel.moveScene(sourceURL, toChapterDirectory: chapter.url, before: targetScene?.url) }
        return true
    }

    /// Drag-to-reorder for a flat section (Front Matter, Back Matter, Notes).
    private func moveFlatSection(_ scenes: [SceneNode], from source: IndexSet, to destination: Int) {
        var urls = scenes.map(\.url)
        urls.move(fromOffsets: source, toOffset: destination)
        Task { await projectViewModel.reorder(orderedURLs: urls) }
    }

    /// A Notes row: a markdown note opens in the editor like any other scene; a
    /// dropped-in reference document (PDF, image, anything non-markdown) instead
    /// shows an "Open"/"Show in Finder" detail pane (§ attachmentDetail below) since
    /// the editor can't display it.
    @ViewBuilder
    private func noteRow(_ note: SceneNode) -> some View {
        Label(note.displayName, systemImage: isMarkdownFile(note.url) ? "doc.text" : "paperclip")
            .tag(note.url)
            .foregroundStyle(Theme.Color.text)
            .listRowBackground(rowBackground(for: note.url))
            .contextMenu {
                if !isMarkdownFile(note.url) {
                    Button("Open") { NSWorkspace.shared.open(note.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                    Divider()
                }
                binderRenameDeleteMenu(url: note.url, currentTitle: note.displayName, isChapter: false)
            }
    }

    private func isMarkdownFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "md"
    }

    /// The book cover's on-disk location (§4.5's `compile.coverImage`), or `nil` if
    /// none has been set yet or the file it points at no longer exists.
    private var coverImageURL: URL? {
        guard let root = projectViewModel.workingTreeRoot, let path = projectViewModel.metadata?.compile.coverImage
        else { return nil }
        let url = root.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A pinned first row in Front Matter showing the current cover (or a hint that
    /// there isn't one yet) — otherwise a dropped-in cover has no visible trace
    /// anywhere in the binder, since it lives in `Resources/`, not as a scene.
    @ViewBuilder
    private var coverImageRow: some View {
        if let coverImageURL {
            HStack(spacing: 8) {
                // A thumbnail that fails to decode (an unusual format, a corrupt
                // file) must not hide the row's only "Remove" affordance behind it —
                // fall back to a generic icon rather than treating decode failure as
                // "no cover set".
                if let nsImage = NSImage(contentsOf: coverImageURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.Color.textMuted)
                }
                Text("Cover: \(coverImageURL.lastPathComponent)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
                // A visible button, not just a context menu — a lone right-click-only
                // affordance on an otherwise static row is easy to miss entirely.
                Button {
                    Task { await projectViewModel.removeCoverImage() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.textMuted)
                .help("Remove Cover Image")
            }
            .contentShape(Rectangle())
            .listRowBackground(SwiftUI.Color.clear)
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([coverImageURL]) }
                Button("Remove Cover Image", role: .destructive) { Task { await projectViewModel.removeCoverImage() } }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.Color.textMuted)
                Text("No cover image — drop one here")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
            }
            .listRowBackground(SwiftUI.Color.clear)
        }
    }

    private var notesDirectoryURL: URL? {
        projectViewModel.workingTreeRoot?.appendingPathComponent("Notes")
    }

    /// ⌥⌘⇧N's target chapter: whichever chapter contains the current selection (a
    /// scene, or the chapter row itself), falling back to the last chapter so the
    /// shortcut still does something sensible with a loose-file chapter, a Front/Back
    /// Matter/Notes item, or nothing at all selected. `nil` only when the manuscript
    /// has no real (non-loose-file) chapter to add a scene to yet.
    private var chapterURLForNewScene: URL? {
        guard let tree = projectViewModel.binderTree else { return nil }
        let chapters = tree.manuscript.filter { !$0.isLooseFile }
        if let selectedSceneURL {
            if let ownChapter = chapters.first(where: { $0.url == selectedSceneURL }) {
                return ownChapter.url
            }
            if let containingChapter = chapters.first(where: { chapter in chapter.scenes.contains { $0.url == selectedSceneURL } }) {
                return containingChapter.url
            }
        }
        return chapters.last?.url
    }

    /// ⌘⌫'s target: the same confirmation dialog the context menu's "Delete…" already
    /// uses, for whichever binder row is currently selected — a no-op with nothing
    /// selected, rather than guessing.
    private func requestDeleteSelection() {
        guard let url = selectedSceneURL, let tree = projectViewModel.binderTree else { return }
        if let chapter = tree.manuscript.first(where: { $0.url == url }) {
            deleteTarget = BinderDeleteTarget(url: chapter.url, displayName: chapter.displayName, isChapter: true)
            return
        }
        let flatSections = [tree.frontMatter, tree.backMatter, tree.notes] + tree.manuscript.map(\.scenes)
        for section in flatSections {
            if let scene = section.first(where: { $0.url == url }) {
                deleteTarget = BinderDeleteTarget(url: scene.url, displayName: scene.displayName, isChapter: false)
                return
            }
        }
    }

    /// Finder-drop handler for the Notes section: copies every dropped file in as-is.
    private func handleNotesDrop(_ urls: [URL]) -> Bool {
        guard let notesDirectoryURL, !urls.isEmpty else { return false }
        Task {
            for url in urls {
                _ = await projectViewModel.importFile(from: url, into: notesDirectoryURL)
            }
            toastCenter.show(urls.count == 1 ? "Added to Notes" : "Added \(urls.count) files to Notes")
        }
        return true
    }

    /// Finder-drop handler for the Front Matter section: the first dropped image
    /// becomes the book cover (§4.5). Non-image drops are ignored rather than added
    /// as a binder row, since Front Matter is template-generated `.md` only.
    private func handleCoverImageDrop(_ urls: [URL]) -> Bool {
        guard
            let imageURL = urls.first(where: { url in
                (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
            })
        else {
            toastCenter.show("Only image files can be set as the cover")
            return false
        }
        Task {
            if await projectViewModel.setCoverImage(from: imageURL) {
                toastCenter.show("Cover image set — see Front Matter")
            }
        }
        return true
    }

    @ViewBuilder
    private func regenerateMenuItem(for scene: SceneNode) -> some View {
        if let template = FrontBackMatterTemplate.matching(filename: scene.url.lastPathComponent) {
            Button("Regenerate from Template") {
                regenerateConfirmation = (template, scene.displayName)
            }
        }
    }

    private func generateMissingFrontBackMatter() {
        guard let metadata = projectViewModel.metadata, let root = projectViewModel.workingTreeRoot else { return }
        do {
            _ = try FrontBackMatterService.generateMissing(metadata: metadata, workingTree: root, fileWriter: LiveAtomicFileWriter())
            Task { await projectViewModel.refresh() }
        } catch {
            frontBackMatterError = error.localizedDescription
        }
    }

    private func performRegenerate() {
        defer { regenerateConfirmation = nil }
        guard let pending = regenerateConfirmation, let metadata = projectViewModel.metadata,
            let root = projectViewModel.workingTreeRoot
        else { return }
        do {
            try FrontBackMatterService.regenerate(
                template: pending.template,
                metadata: metadata,
                workingTree: root,
                fileWriter: LiveAtomicFileWriter()
            )
            if let sceneURL = selectedSceneURL, sceneURL.lastPathComponent == pending.template.filename {
                sceneEditor.open(url: sceneURL)
            }
        } catch {
            frontBackMatterError = error.localizedDescription
        }
    }

    private func isOpenableScene(_ url: URL) -> Bool {
        guard let tree = projectViewModel.binderTree else { return false }
        let inManuscript = tree.manuscript.contains { chapter in
            (chapter.isLooseFile && chapter.url == url) || chapter.scenes.contains { $0.url == url }
        }
        return inManuscript
            || tree.frontMatter.contains { $0.url == url }
            || tree.backMatter.contains { $0.url == url }
            || tree.notes.contains { $0.url == url }
    }

    private var sceneBodyBinding: Binding<String> {
        Binding(
            get: { sceneEditor.document?.body ?? "" },
            set: { sceneEditor.updateBody($0) }
        )
    }
}

/// Identifies which binder item the "Rename…" sheet is renaming.
private struct BinderRenameTarget: Identifiable {
    let url: URL
    let currentTitle: String
    var id: URL { url }
}

/// Identifies which binder item the delete confirmation is about to remove.
private struct BinderDeleteTarget: Identifiable {
    let url: URL
    let displayName: String
    let isChapter: Bool
    var id: URL { url }
}

#Preview {
    ContentView()
}
