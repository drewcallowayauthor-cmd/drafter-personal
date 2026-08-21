import CredentialStore
import DrafterCore
import Foundation
import GitService
import Observation
import ProjectStore
import SnapshotService

/// Opens (or creates) a project folder and exposes a read-only snapshot for
/// `ContentView`'s binder list, plus the git wiring (§7): a repo is initialized
/// in-place if missing, `autocommitScheduler` is exposed so the editor can report
/// activity into it, and a brand-new project is optionally connected to GitHub (§5.2).
@MainActor
@Observable
final class ProjectViewModel {
    private(set) var metadata: ProjectMetadata?
    private(set) var binderTree: BinderTree?
    private(set) var errorMessage: String?
    private(set) var autocommitScheduler: AutocommitScheduler?
    /// `nil` for a local-only project (no `origin` remote configured) — §5.5's sync
    /// loop has nothing to do without a remote, so it's simply never started rather
    /// than running and failing every pass.
    private(set) var syncScheduler: SyncScheduler?
    /// Shared with `HistoryViewModel` (§5.8) so it isn't standing up a second actor
    /// against the same working tree. `nil` for a Local-file-mode project.
    private(set) var gitService: GitService?
    /// Local-file mode's counterpart to `gitService`, §7.
    private(set) var snapshotService: SnapshotService?
    private var snapshotCoordinator: SnapshotCoordinator?
    /// Whichever of `gitService`/`snapshotService` is live for the open project — what
    /// `HistoryViewModel` (§9.1) actually needs, without caring which mode it is.
    private(set) var versioningSource: (any VersioningSource)?
    private(set) var workingTreeRoot: URL?
    /// Non-fatal: set after `createNewProject` regardless of whether GitHub connection
    /// succeeded. §5.2 — a project that failed to connect is still fully usable
    /// locally, so this never blocks `metadata`/`binderTree` from being populated.
    private(set) var syncStatusMessage: String?
    /// §6.4's no-lock-file concurrent-editing check — set on open and on focus regain.
    private(set) var concurrentEditingWarning: ConcurrentEditingWarning.Info?

    /// §6.3: called (already debounced, on the main actor) whenever the working tree
    /// changes on disk from outside the app. `ContentView` sets this to refresh the
    /// binder and apply the open-scene reload rules; `ProjectViewModel` itself only
    /// owns the watcher's lifecycle, not what "reload" means for an open editor.
    var onExternalChange: ((Set<URL>) -> Void)?

    private var project: Project?
    private var fileSystemWatcher: FileSystemWatcher?
    /// The root this window currently holds a lock on in `OpenProjectRegistry`
    /// (§12.2 point 7) — `nil` when no project is open. Tracked separately from
    /// `workingTreeRoot` so `attach` can tell "reconnecting the same project" (skip
    /// the registry check) apart from "opening a different one" (release the old
    /// lock, take a new one).
    /// Boxed in a plain (non-`@Observable`, non-`@MainActor`) holder so `deinit`
    /// (which runs non-isolated even on a `@MainActor` class) can read it to release
    /// the lock when a window closes without an explicit `closeProject()`, without the
    /// compiler misreporting `nonisolated(unsafe)` as having "no effect" the way it
    /// did as a direct stored property here — plain `nonisolated` is rejected outright
    /// on any mutable stored property in Swift, `@Observable` or not, so `(unsafe)`
    /// genuinely is required; the warning was simply wrong. Safety comes from nothing
    /// else touching this once `deinit` has started, same as before.
    private let registeredRootBox = RegisteredRootBox()
    private var registeredRoot: URL? {
        get { registeredRootBox.value }
        set { registeredRootBox.value = newValue }
    }

    deinit {
        if let root = registeredRootBox.value {
            Task { await OpenProjectRegistry.shared.unregister(root) }
        }
    }

    /// Every operation below that mutates `self.project`/`registeredRoot`/the
    /// schedulers (`open`, `createNewProject`, `cloneProject`, `connectToGitHub`,
    /// `refreshCredentialsAndResync`, `closeProject`) spans many `await` points while
    /// building up that state incrementally rather than atomically. Nothing prevented
    /// two of them from interleaving — e.g. the concurrent-editing alert's "Cancel"
    /// (`closeProject`) firing while an in-flight `open`'s `attach()` was still
    /// mid-flight, so `reset()` would run, then the original `attach()` would resume
    /// and keep assigning schedulers into a project that was supposedly just closed.
    /// Routing every entry point through this queue makes them run strictly one after
    /// another regardless of call order, so no interleaving like that can happen.
    private var operationQueue: Task<Void, Never> = Task {}

    private func serialized(_ operation: @escaping () async -> Void) async {
        let previous = operationQueue
        let task = Task {
            _ = await previous.value
            await operation()
        }
        operationQueue = task
        await task.value
    }

    func open(root: URL) async {
        await serialized { await self.openImpl(root: root) }
    }

    private func openImpl(root: URL) async {
        errorMessage = nil
        do {
            let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
            let metadata = await project.metadata
            // §14.1: only Git mode's `.git` is at risk inside a cloud-sync folder —
            // Local-file mode expects to live there (§4.1), so it skips the guard.
            if metadata.versionControl == .git, let guardError = SyncedFolderGuard.check(root) {
                throw guardError
            }
            try await attach(project: project, root: root, metadata: metadata)
        } catch {
            await reset()
            errorMessage = error.localizedDescription
        }
    }

    /// General pane's "reopen last project on launch" (§12): behaves like `open(root:)`
    /// but never surfaces a failure — the writer never asked for this attempt, so a
    /// moved/deleted last project should fall back to the welcome screen quietly rather
    /// than greet them with an alert before they've done anything.
    func openSilently(root: URL) async {
        await open(root: root)
        if metadata == nil {
            errorMessage = nil
        }
    }

    /// §5.2/M0's "create project folder" flow: scaffolds the folder structure and
    /// `project.json`, initializes git, makes the initial commit, then — if a GitHub
    /// token is already saved (§5.3) — creates a private repo and connects it. A
    /// missing token, a taken repo name, or being offline all fall back to a
    /// fully-functional local-only project (§5.2's "GitHub is not a prerequisite for
    /// writing"), reflected in `syncStatusMessage` rather than `errorMessage`.
    func createNewProject(
        title: String,
        author: String,
        location: URL? = nil,
        versionControl: VersionControlMode = .git,
        manuscriptTemplate: ManuscriptTemplate = .novel
    ) async {
        await serialized {
            await self.createNewProjectImpl(
                title: title,
                author: author,
                location: location,
                versionControl: versionControl,
                manuscriptTemplate: manuscriptTemplate
            )
        }
    }

    private func createNewProjectImpl(
        title: String,
        author: String,
        location: URL?,
        versionControl: VersionControlMode,
        manuscriptTemplate: ManuscriptTemplate
    ) async {
        errorMessage = nil
        syncStatusMessage = nil
        do {
            let slug = Self.slug(for: title)
            let root = (location ?? Self.defaultProjectsDirectory()).appendingPathComponent(slug)
            // §14.1: the hard block is Git-mode-only — Local-file mode is meant to be
            // creatable inside a cloud-sync folder (§4.1/§5).
            if versionControl == .git, let guardError = SyncedFolderGuard.check(root) {
                throw guardError
            }

            let metadata = ProjectMetadata(
                title: title,
                author: author,
                versionControl: versionControl,
                copyrightYear: Calendar.current.component(.year, from: .now),
                compile: ProjectMetadata.Compile(chapterTitleFormat: manuscriptTemplate.defaultChapterTitleFormat)
            )
            let project = try Project.create(root: root, metadata: metadata, fileWriter: LiveAtomicFileWriter())

            switch versionControl {
            case .git:
                let token = await Self.loadTokenIfAvailable()
                let gitService = Self.makeGitService(authToken: token)
                let repositoryCoordinator = RepositoryCoordinator(gitService: gitService, workingTree: root)
                try await repositoryCoordinator.ensureInitialized(authorName: author)
                _ = try await repositoryCoordinator.commit(trigger: .checkpoint(label: "initial commit"))

                await connectToGitHubIfPossible(
                    repositoryName: slug,
                    authorName: author,
                    repositoryCoordinator: repositoryCoordinator,
                    token: token
                )

                try await attach(
                    project: project,
                    root: root,
                    gitService: gitService,
                    repositoryCoordinator: repositoryCoordinator,
                    metadata: metadata
                )

            case .localFile:
                // §7.2's "initial snapshot" — the Local-file equivalent of Git mode's
                // initial commit, so the project has a first History entry from the
                // moment it's created rather than only after the first edit.
                let snapshotCoordinator = SnapshotCoordinator(snapshotService: SnapshotService(), workingTree: root)
                _ = try await snapshotCoordinator.commit(trigger: .checkpoint(label: "initial snapshot"))
                try await attach(project: project, root: root, metadata: metadata)
            }
        } catch {
            await reset()
            errorMessage = error.localizedDescription
        }
    }

    /// §5.9's "Add Existing Project" path — clones one of the repos from
    /// `GitHubRepoPickerViewModel`'s list into the default projects location, then
    /// opens it like any other project. Requires a saved token (the picker can't have
    /// listed anything without one), and reuses it so the clone of a private repo
    /// actually authenticates.
    func cloneProject(_ repository: GitHubRepository) async {
        await serialized { await self.cloneProjectImpl(repository) }
    }

    private func cloneProjectImpl(_ repository: GitHubRepository) async {
        errorMessage = nil
        syncStatusMessage = nil
        do {
            let root = Self.defaultProjectsDirectory().appendingPathComponent(repository.name)
            if let guardError = SyncedFolderGuard.check(root) { throw guardError }

            try FileManager.default.createDirectory(
                at: Self.defaultProjectsDirectory(),
                withIntermediateDirectories: true
            )

            let token = await Self.loadTokenIfAvailable()
            let gitService = Self.makeGitService(authToken: token)
            try await gitService.clone(url: repository.cloneURL.absoluteString, to: root)

            let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
            try await attach(project: project, root: root, gitService: gitService)
        } catch {
            await reset()
            errorMessage = error.localizedDescription
        }
    }

    /// §5.2's "Connect to GitHub" action for a project that's open but not yet synced
    /// — it predates having a saved token, or GitHub connection failed when it was
    /// created (§5.2: "still create the project locally... mark it Not synced with a
    /// Connect to GitHub action"). Rebuilds this project's git wiring via `attach`
    /// afterward so the newly-added remote actually starts the sync loop, rather than
    /// leaving `syncScheduler` nil until the next reopen.
    func connectToGitHub() async {
        await serialized { await self.connectToGitHubImpl() }
    }

    private func connectToGitHubImpl() async {
        errorMessage = nil
        syncStatusMessage = nil
        guard let project, let workingTreeRoot, let metadata, metadata.versionControl == .git else { return }
        guard let token = await Self.loadTokenIfAvailable(), !token.isEmpty else {
            syncStatusMessage = "Add a GitHub token in Settings first."
            return
        }

        let freshGitService = Self.makeGitService(authToken: token)
        if await Self.hasRemoteLogging(freshGitService, in: workingTreeRoot) {
            syncStatusMessage = "Already connected to GitHub."
            return
        }

        let repositoryCoordinator = RepositoryCoordinator(gitService: freshGitService, workingTree: workingTreeRoot)
        do {
            let repository = try await repositoryCoordinator.connectToGitHub(
                repositoryName: Self.slug(for: metadata.title),
                authorName: metadata.author,
                apiClient: GitHubAPIClient(),
                token: token
            )
            syncStatusMessage = "Synced to \(repository.htmlURL.absoluteString)"
            try await attach(
                project: project,
                root: workingTreeRoot,
                gitService: freshGitService,
                repositoryCoordinator: repositoryCoordinator,
                metadata: metadata
            )
        } catch {
            syncStatusMessage = "Couldn't connect to GitHub — \(error.localizedDescription)"
        }
    }

    /// Best-effort — failures here are §5.2's "Not synced" path, not a thrown error.
    private func connectToGitHubIfPossible(
        repositoryName: String,
        authorName: String,
        repositoryCoordinator: RepositoryCoordinator,
        token: String?
    ) async {
        guard let token else {
            syncStatusMessage = "Not synced to GitHub"
            return
        }
        do {
            let repository = try await repositoryCoordinator.connectToGitHub(
                repositoryName: repositoryName,
                authorName: authorName,
                apiClient: GitHubAPIClient(),
                token: token
            )
            syncStatusMessage = "Synced to \(repository.htmlURL.absoluteString)"
        } catch {
            syncStatusMessage = "Not synced to GitHub — \(error.localizedDescription)"
        }
    }

    /// Shared tail of `open` and `createNewProject`: populate the observable snapshot
    /// once a `Project` and its git wiring both exist. `createNewProject` already has
    /// its own `GitService`/`RepositoryCoordinator` (it needed them earlier, to make
    /// the initial commit and connect to GitHub); `open` builds fresh ones.
    private func attach(
        project: Project,
        root: URL,
        gitService: GitService? = nil,
        repositoryCoordinator: RepositoryCoordinator? = nil,
        metadata: ProjectMetadata? = nil
    ) async throws {
        if registeredRoot != root {
            if let registeredRoot {
                await OpenProjectRegistry.shared.unregister(registeredRoot)
                self.registeredRoot = nil
            }
            guard await OpenProjectRegistry.shared.tryRegister(root) else {
                throw DrafterError.projectAlreadyOpen(path: root.path)
            }
            registeredRoot = root
        }

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
        RecentProjects.record(title: resolvedMetadata.title.isEmpty ? root.lastPathComponent : resolvedMetadata.title, root: root)
        AppPreferences.shared.lastOpenedProjectPath = root.path
        AppPreferences.shared.lastPickedVersionControlMode = resolvedMetadata.versionControl.rawValue

        fileSystemWatcher?.stop()
        let watcher = FileSystemWatcher(path: root) { [weak self] changedURLs in self?.onExternalChange?(changedURLs) }
        watcher.start()
        fileSystemWatcher = watcher

        // Tear down whichever mode's wiring is currently live before rebuilding —
        // `refreshCredentialsAndResync` and `connectToGitHub` both call back into this
        // for an already-open project.
        self.gitService = nil
        snapshotService = nil
        snapshotCoordinator = nil
        versioningSource = nil
        syncScheduler?.stop()
        syncScheduler = nil
        concurrentEditingWarning = nil

        switch resolvedMetadata.versionControl {
        case .git:
            // Whether this call built its own `GitService` (`gitService` was `nil`)
            // rather than being handed an already-authenticated one by a caller that
            // just connected to GitHub itself (`createNewProject`, `cloneProject`,
            // `connectToGitHub`) — only the former needs the remote-gated Keychain
            // check just below.
            let builtOwnGitService = gitService == nil
            let resolvedGitService: GitService
            if let gitService {
                resolvedGitService = gitService
            } else {
                // §12.2 point 8: don't touch the Keychain yet. Local git init and
                // local commits (right below) need no token at all, and most opens
                // won't turn out to have a GitHub remote in the first place (§5.2:
                // "GitHub is not a prerequisite for writing") — the token is only
                // worth a Keychain round-trip once a remote is confirmed to exist.
                resolvedGitService = Self.makeGitService(authToken: nil)
            }
            self.gitService = resolvedGitService
            versioningSource = resolvedGitService

            let resolvedCoordinator: RepositoryCoordinator
            if let repositoryCoordinator {
                resolvedCoordinator = repositoryCoordinator
            } else {
                resolvedCoordinator = RepositoryCoordinator(gitService: resolvedGitService, workingTree: root)
                try await resolvedCoordinator.ensureInitialized(authorName: resolvedMetadata.author)
            }
            let scheduler = AutocommitScheduler(
                checkpointCoordinator: resolvedCoordinator,
                debounceDelay: .seconds(AppPreferences.shared.autocommitDebounceSeconds)
            )
            autocommitScheduler = scheduler

            if await Self.hasRemoteLogging(resolvedGitService, in: root) {
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

        case .localFile:
            let resolvedSnapshotService = SnapshotService()
            self.snapshotService = resolvedSnapshotService
            versioningSource = resolvedSnapshotService

            let coordinator = SnapshotCoordinator(snapshotService: resolvedSnapshotService, workingTree: root)
            snapshotCoordinator = coordinator
            autocommitScheduler = AutocommitScheduler(
                checkpointCoordinator: coordinator,
                debounceDelay: .seconds(AppPreferences.shared.autocommitDebounceSeconds)
            )

            // §7.6: display-only — never a network call, just a heuristic on the
            // resolved path, so this is safe to do unconditionally and immediately.
            if let provider = SnapshotService.cloudProvider(for: root) {
                syncStatusMessage = "Saved — syncing via \(provider)"
            } else {
                syncStatusMessage = "Saved — not in a synced folder"
            }
            await checkConcurrentEditingLocalFile()
        }

        switch resolvedMetadata.versionControl {
        case .git:
            if let gitService { OpenProjectHandle.shared.setGit(workingTreeRoot: root, gitService: gitService) }
        case .localFile:
            if let snapshotService { OpenProjectHandle.shared.setLocalFile(workingTreeRoot: root, snapshotService: snapshotService) }
        }
    }

    /// §8.3, called on project open (via `attach`) and again whenever the window
    /// regains focus. Dispatches on the open project's mode — Git mode checks
    /// `origin/main`, Local-file mode checks `History/`.
    func checkConcurrentEditing() async {
        switch metadata?.versionControl {
        case .git: await checkConcurrentEditingGit()
        case .localFile: await checkConcurrentEditingLocalFile()
        case nil: return
        }
    }

    private func checkConcurrentEditingGit() async {
        guard let gitService, let workingTreeRoot else { return }
        do {
            try await gitService.fetch(in: workingTreeRoot)
        } catch {
            DrafterLog.app.error("Background fetch for the concurrent-editing check failed: \(error, privacy: .public)")
        }
        concurrentEditingWarning = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTreeRoot,
            ownMachineName: RepositoryCoordinator.defaultMachineName()
        )
    }

    private func checkConcurrentEditingLocalFile() async {
        guard let snapshotService, let workingTreeRoot else { return }
        concurrentEditingWarning = await ConcurrentEditingWarning.checkLocalFile(
            snapshotService: snapshotService,
            workingTree: workingTreeRoot,
            ownMachineName: RepositoryCoordinator.defaultMachineName()
        )
    }

    /// §12.2 point 4's resolution: called when Settings saves a newly verified token.
    /// `GitService.authToken` is immutable once constructed, so simply retrying with
    /// the existing `syncScheduler` would just fail the same way again with the same
    /// stale token — this rebuilds the project's git wiring (via `attach`, same as a
    /// fresh open) so the new token actually gets used, then that rebuild's own
    /// `SyncScheduler.start()` retries immediately rather than waiting out the next
    /// periodic tick.
    func refreshCredentialsAndResync() async {
        await serialized { await self.refreshCredentialsAndResyncImpl() }
    }

    private func refreshCredentialsAndResyncImpl() async {
        guard let project, let workingTreeRoot, let metadata, metadata.versionControl == .git else { return }
        errorMessage = nil
        let token = await Self.loadTokenIfAvailable()
        let gitService = Self.makeGitService(authToken: token)
        do {
            try await attach(project: project, root: workingTreeRoot, gitService: gitService, metadata: metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The stored token is best-effort throughout this file: most opens have no
    /// GitHub remote at all, so a Keychain miss/failure just falls back to an
    /// unauthenticated `GitService` rather than blocking the open — but a failure that
    /// isn't "there's simply no token saved" should still leave a trace rather than
    /// silently behaving as if the user were never connected.
    private static func loadTokenIfAvailable() async -> String? {
        do {
            return try await CredentialStore().loadToken()
        } catch {
            DrafterLog.app.error("Failed to load the saved GitHub token: \(error, privacy: .public)")
            return nil
        }
    }

    /// Tools pane's git override (§12), falling back to `GitService`'s own
    /// `/usr/bin/git` default when unset.
    private static func makeGitService(authToken: String?) -> GitService {
        if let overridePath = AppPreferences.shared.gitPathOverride {
            return GitService(processRunner: LiveProcessRunner(), gitExecutableURL: URL(fileURLWithPath: overridePath), authToken: authToken)
        }
        return GitService(processRunner: LiveProcessRunner(), authToken: authToken)
    }

    /// A failed `remoteURL` check is treated the same as "no remote configured yet" —
    /// worst case this re-attempts a connect that turns out to already exist, which
    /// `RepositoryCoordinator.connectToGitHub` handles gracefully — but it's still
    /// worth a log line so a spurious "reconnect" isn't a total mystery later.
    private static func hasRemoteLogging(_ gitService: GitService, in workingTree: URL) async -> Bool {
        do {
            return try await gitService.remoteURL(in: workingTree) != nil
        } catch {
            DrafterLog.app.error("Failed to check for an existing remote: \(error, privacy: .public)")
            return false
        }
    }

    /// Dismisses the concurrent-editing warning's "Cancel" option (§8.3) — backs out
    /// of the project rather than risking an edit alongside another machine.
    func closeProject() async {
        await serialized { await self.closeProjectImpl() }
    }

    private func closeProjectImpl() async {
        // §7.3's thinning, mirroring Git mode's `git gc --auto` on close — best-effort,
        // never blocks actually closing the project.
        try? await snapshotCoordinator?.pruneSnapshots()
        await reset()
    }

    /// `async` (rather than a fire-and-forget `Task` around the registry unregister)
    /// so a caller that awaits `closeProject()`/a failed `open` can rely on the root
    /// being free *before* the next statement runs — e.g. immediately reopening the
    /// same project, or a second window's `open` racing this one's teardown.
    private func reset() async {
        if let registeredRoot {
            await OpenProjectRegistry.shared.unregister(registeredRoot)
        }
        registeredRoot = nil
        OpenProjectHandle.shared.clear()
        project = nil
        metadata = nil
        binderTree = nil
        autocommitScheduler = nil
        syncScheduler?.stop()
        syncScheduler = nil
        fileSystemWatcher?.stop()
        fileSystemWatcher = nil
        gitService = nil
        snapshotService = nil
        snapshotCoordinator = nil
        versioningSource = nil
        workingTreeRoot = nil
        syncStatusMessage = nil
        concurrentEditingWarning = nil
    }

    static func defaultProjectsDirectory() -> URL {
        if let overridePath = AppPreferences.shared.projectsDirectoryPath {
            return URL(fileURLWithPath: overridePath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Drafter/Projects")
    }

    /// Slugifies a title into a filesystem- and GitHub-repo-safe folder/repo name
    /// (§5.2: "Slugify the title → `the-last-shift`").
    nonisolated static func slug(for title: String) -> String {
        let lowered = title.lowercased()
        let slugged = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(slugged)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "untitled" : collapsed
    }

    /// Dismisses the concurrent-editing warning's "Continue" option (§6.4).
    func acknowledgeConcurrentEditingWarning() {
        concurrentEditingWarning = nil
    }

    /// Dismisses the one-shot "New Project" sync-status alert.
    func acknowledgeSyncStatus() {
        syncStatusMessage = nil
    }

    func refresh() async {
        guard let project else { return }
        do {
            try await project.refreshBinderTree()
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §8.2's "New Chapter" — returns the seeded scene's URL on success so
    /// `ContentView` can select and open it immediately.
    func createChapter(title: String) async -> URL? {
        guard let project else { return nil }
        do {
            let sceneURL = try await project.createChapter(title: title, fileWriter: LiveAtomicFileWriter())
            binderTree = await project.binderTree
            return sceneURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's "New Scene" — `directory` is a chapter folder, or one of the flat
    /// FrontMatter/BackMatter/Notes sections.
    func createScene(title: String, in directory: URL) async -> URL? {
        guard let project else { return nil }
        do {
            let sceneURL = try await project.createScene(title: title, in: directory, fileWriter: LiveAtomicFileWriter())
            binderTree = await project.binderTree
            return sceneURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's binder rename — returns the item's new URL on success so `ContentView`
    /// can follow a rename of the currently-open/selected scene.
    @discardableResult
    func rename(itemAt url: URL, to newTitle: String) async -> URL? {
        guard let project else { return nil }
        do {
            let newURL = try await project.rename(itemAt: url, to: newTitle)
            binderTree = await project.binderTree
            return newURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's binder delete — removes a scene file or an entire chapter folder.
    func delete(itemAt url: URL) async {
        guard let project else { return }
        do {
            try await project.delete(itemAt: url)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §4.3/§8.2's drag-to-reorder — `orderedURLs` must all share one directory (a
    /// chapter's scenes, a flat section, or Manuscript's chapters).
    func reorder(orderedURLs: [URL]) async {
        guard let project else { return }
        do {
            try await project.reorder(orderedURLs: orderedURLs)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §8.2's cross-chapter drag — moves a scene into `chapterDirectory` (possibly
    /// its current one, for a same-chapter reorder), inserting it immediately
    /// before `targetURL`, or at the end when `targetURL` is `nil`.
    func moveScene(_ url: URL, toChapterDirectory chapterDirectory: URL, before targetURL: URL?) async {
        guard let project else { return }
        do {
            try await project.moveScene(at: url, toChapterDirectory: chapterDirectory, before: targetURL)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drag-and-drop (or a future file picker) import of an external file into a flat
    /// binder section — currently Notes, which accepts any file type for reference
    /// documents. Returns the copy's URL so the caller can select it.
    func importFile(from sourceURL: URL, into directory: URL) async -> URL? {
        guard let project else { return nil }
        do {
            let importedURL = try await project.importFile(from: sourceURL, into: directory)
            binderTree = await project.binderTree
            return importedURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Sets the book cover from an external image (dropped onto Front Matter, or
    /// chosen from Settings) — copies it into `Resources/` and updates
    /// `compile.coverImage` (§4.5).
    @discardableResult
    func setCoverImage(from sourceURL: URL) async -> Bool {
        guard let project else { return false }
        do {
            _ = try await project.setCoverImage(from: sourceURL, fileWriter: LiveAtomicFileWriter())
            metadata = await project.metadata
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Deletes the current cover image file. Leaves `compile.coverImage`'s path as-is
    /// rather than clearing it — every consumer (export, the Front Matter cover row)
    /// already checks the file exists before using it, so a dangling path is harmless.
    func removeCoverImage() async {
        guard let workingTreeRoot, let metadata else { return }
        errorMessage = nil
        do {
            try FileManager.default.removeItem(at: workingTreeRoot.appendingPathComponent(metadata.compile.coverImage))
        } catch {
            errorMessage = "Couldn't remove the cover image: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// §8.3 point 8's project-wide find (⇧⌘F).
    func search(options: ProjectSearchOptions) async -> [ProjectSearchMatch] {
        guard let project else { return [] }
        return await project.search(options: options)
    }

    /// Applies a batch of replacements. Returns the scene URLs actually rewritten so
    /// the caller can reload any of them that's currently open in the editor.
    @discardableResult
    func replace(matches: [ProjectSearchMatch], replacement: String) async -> Set<URL> {
        guard let project else { return [] }
        do {
            return try await project.replace(matches: matches, replacement: replacement, fileWriter: LiveAtomicFileWriter())
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Saves an edited copy of `project.json` (§4.5) — the metadata editor works on a
    /// local draft and only calls this on explicit confirmation.
    @discardableResult
    func save(metadata: ProjectMetadata) async -> Bool {
        guard let project else { return false }
        do {
            try await project.save(metadata: metadata)
            self.metadata = metadata
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// See `ProjectViewModel.registeredRoot`'s doc comment.
private final class RegisteredRootBox: @unchecked Sendable {
    nonisolated(unsafe) var value: URL?
}
