import GitService
import SwiftUI

extension ContentView {
    @ViewBuilder
    func withProjectSheets(_ content: some View) -> some View {
        withImportAndCompileSheets(
            withRenameAndCreateProjectSheets(
                withNewNoteSheet(withNewChapterAndSceneSheets(withConflictSheets(withOnboardingSheets(content))))
            )
        )
    }

    @ViewBuilder
    private func withOnboardingSheets(_ content: some View) -> some View {
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
                        await projectViewModel.autocommitScheduler?.flush(
                            trigger: .checkpoint(label: "manual snapshot")
                        )
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
    }

    @ViewBuilder
    private func withConflictSheets(_ content: some View) -> some View {
        content
        .onChange(of: projectViewModel.syncScheduler?.state) { _, newState in
            if case .conflicted = newState {
                isConflictSheetPresented = true
            }
        }
        .sheet(isPresented: $isConflictSheetPresented) {
            if case .conflicted(let paths) = projectViewModel.syncScheduler?.state,
                let gitService = projectViewModel.gitService, let workingTree = projectViewModel.workingTreeRoot {
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
    }

    @ViewBuilder
    private func withNewChapterAndSceneSheets(_ content: some View) -> some View {
        content
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
    }

    @ViewBuilder
    private func withNewNoteSheet(_ content: some View) -> some View {
        content
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
    }

    @ViewBuilder
    private func withRenameAndCreateProjectSheets(_ content: some View) -> some View {
        content
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
    }

    @ViewBuilder
    private func withImportAndCompileSheets(_ content: some View) -> some View {
        content
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
                let workingTree = projectViewModel.workingTreeRoot {
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
                performReplace: { matches, replacement in
                    await projectViewModel.replace(matches: matches, replacement: replacement)
                },
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
}
