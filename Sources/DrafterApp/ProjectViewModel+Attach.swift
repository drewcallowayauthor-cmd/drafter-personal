import DrafterCore
import Foundation
import GitService
import ProjectStore
import SnapshotService

/// `attach(project:root:gitService:repositoryCoordinator:metadata:)` — the shared tail
/// of `open` and `createNewProject` that populates the observable snapshot once a
/// `Project` and its git/local-file wiring both exist — split out into its own file,
/// and its body broken into smaller pieces, to keep `ProjectViewModel`'s file/type-body
/// lengths and this function's own body length/cyclomatic complexity under SwiftLint's
/// limits.
extension ProjectViewModel {
    /// `createNewProject` already has its own `GitService`/`RepositoryCoordinator` (it
    /// needed them earlier, to make the initial commit and connect to GitHub); `open`
    /// builds fresh ones.
    func attach(
        project: Project,
        root: URL,
        gitService: GitService? = nil,
        repositoryCoordinator: RepositoryCoordinator? = nil,
        metadata: ProjectMetadata? = nil
    ) async throws {
        try await registerRootIfNeeded(root: root)
        let resolvedMetadata = await populateCoreState(project: project, root: root, metadata: metadata)
        restartFileWatcher(root: root)

        // Tear down whichever mode's wiring is currently live before rebuilding —
        // `refreshCredentialsAndResync` and `connectToGitHub` both call back into this
        // for an already-open project.
        teardownVersioningWiring()

        switch resolvedMetadata.versionControl {
        case .git:
            try await attachGit(
                root: root, metadata: resolvedMetadata, gitService: gitService,
                repositoryCoordinator: repositoryCoordinator
            )
        case .localFile:
            await attachLocalFile(root: root)
        }

        registerOpenProjectHandle(metadata: resolvedMetadata, root: root)
    }

    private func registerRootIfNeeded(root: URL) async throws {
        guard registeredRoot != root else { return }
        if let registeredRoot {
            await OpenProjectRegistry.shared.unregister(registeredRoot)
            self.registeredRoot = nil
        }
        guard await OpenProjectRegistry.shared.tryRegister(root) else {
            throw DrafterError.projectAlreadyOpen(path: root.path)
        }
        registeredRoot = root
    }

    private func populateCoreState(project: Project, root: URL, metadata: ProjectMetadata?) async -> ProjectMetadata {
        self.project = project
        let resolvedMetadata: ProjectMetadata
        if let metadata {
            resolvedMetadata = metadata
        } else {
            resolvedMetadata = await project.metadata
        }
        self.metadata = resolvedMetadata
        binderTree = await project.binderTree
        workingTreeRoot = root
        RecentProjects.record(
            title: resolvedMetadata.title.isEmpty ? root.lastPathComponent : resolvedMetadata.title, root: root
        )
        AppPreferences.shared.lastOpenedProjectPath = root.path
        AppPreferences.shared.lastPickedVersionControlMode = resolvedMetadata.versionControl.rawValue
        return resolvedMetadata
    }

    private func restartFileWatcher(root: URL) {
        fileSystemWatcher?.stop()
        let watcher = FileSystemWatcher(path: root) { [weak self] changedURLs in self?.onExternalChange?(changedURLs) }
        watcher.start()
        fileSystemWatcher = watcher
    }

    private func teardownVersioningWiring() {
        gitService = nil
        snapshotService = nil
        snapshotCoordinator = nil
        versioningSource = nil
        syncScheduler?.stop()
        syncScheduler = nil
        concurrentEditingWarning = nil
    }

    /// Resolves the `GitService`/`RepositoryCoordinator` to use, starts the autocommit
    /// scheduler, and — only once a remote is confirmed to exist — starts the sync
    /// scheduler too.
    private func attachGit(
        root: URL, metadata: ProjectMetadata, gitService: GitService?, repositoryCoordinator: RepositoryCoordinator?
    ) async throws {
        // Whether this call built its own `GitService` (`gitService` was `nil`) rather
        // than being handed an already-authenticated one by a caller that just
        // connected to GitHub itself (`createNewProject`, `cloneProject`,
        // `connectToGitHub`) — only the former needs the remote-gated Keychain check
        // just below.
        let builtOwnGitService = gitService == nil
        // §12.2 point 8: don't touch the Keychain yet. Local git init and local
        // commits (right below) need no token at all, and most opens won't turn out to
        // have a GitHub remote in the first place (§5.2: "GitHub is not a prerequisite
        // for writing") — the token is only worth a Keychain round-trip once a remote
        // is confirmed to exist.
        let resolvedGitService = gitService ?? Self.makeGitService(authToken: nil)
        self.gitService = resolvedGitService
        versioningSource = resolvedGitService

        let resolvedCoordinator = try await resolveRepositoryCoordinator(
            repositoryCoordinator, gitService: resolvedGitService, root: root, authorName: metadata.author
        )
        let scheduler = AutocommitScheduler(
            checkpointCoordinator: resolvedCoordinator,
            debounceDelay: .seconds(AppPreferences.shared.autocommitDebounceSeconds)
        )
        autocommitScheduler = scheduler

        guard await Self.hasRemoteLogging(resolvedGitService, in: root) else { return }
        await startGitSync(
            root: root, resolvedGitService: resolvedGitService, builtOwnGitService: builtOwnGitService,
            scheduler: scheduler
        )
    }

    private func resolveRepositoryCoordinator(
        _ repositoryCoordinator: RepositoryCoordinator?, gitService: GitService, root: URL, authorName: String
    ) async throws -> RepositoryCoordinator {
        if let repositoryCoordinator { return repositoryCoordinator }
        let coordinator = RepositoryCoordinator(gitService: gitService, workingTree: root)
        try await coordinator.ensureInitialized(authorName: authorName)
        return coordinator
    }

    private func startGitSync(
        root: URL, resolvedGitService: GitService, builtOwnGitService: Bool, scheduler: AutocommitScheduler
    ) async {
        var syncGitService = resolvedGitService
        if builtOwnGitService {
            let token = await Self.loadTokenIfAvailable()
            syncGitService = Self.makeGitService(authToken: token)
            self.gitService = syncGitService
            versioningSource = syncGitService
        }

        let syncCoordinator = SyncCoordinator(
            gitService: syncGitService,
            workingTree: root,
            machineName: RepositoryCoordinator.defaultMachineName()
        )
        let newSyncScheduler = SyncScheduler(
            syncCoordinator: syncCoordinator,
            fetchInterval: .seconds(AppPreferences.shared.syncFetchIntervalSeconds),
            pushDebounceDelay: .seconds(AppPreferences.shared.syncPushDebounceSeconds)
        )
        scheduler.onCommitted = { [weak newSyncScheduler] in newSyncScheduler?.schedulePushAfterCommit() }
        newSyncScheduler.start()
        syncScheduler = newSyncScheduler
        await checkConcurrentEditingGit()
    }

    private func attachLocalFile(root: URL) async {
        let resolvedSnapshotService = SnapshotService()
        snapshotService = resolvedSnapshotService
        versioningSource = resolvedSnapshotService

        let coordinator = SnapshotCoordinator(snapshotService: resolvedSnapshotService, workingTree: root)
        snapshotCoordinator = coordinator
        autocommitScheduler = AutocommitScheduler(
            checkpointCoordinator: coordinator,
            debounceDelay: .seconds(AppPreferences.shared.autocommitDebounceSeconds)
        )

        // §7.6: display-only — never a network call, just a heuristic on the resolved
        // path, so this is safe to do unconditionally and immediately.
        if let provider = SnapshotService.cloudProvider(for: root) {
            syncStatusMessage = "Saved — syncing via \(provider)"
        } else {
            syncStatusMessage = "Saved — not in a synced folder"
        }
        await checkConcurrentEditingLocalFile()
    }

    private func registerOpenProjectHandle(metadata: ProjectMetadata, root: URL) {
        switch metadata.versionControl {
        case .git:
            if let gitService { OpenProjectHandle.shared.setGit(workingTreeRoot: root, gitService: gitService) }
        case .localFile:
            if let snapshotService {
                OpenProjectHandle.shared.setLocalFile(workingTreeRoot: root, snapshotService: snapshotService)
            }
        }
    }
}
