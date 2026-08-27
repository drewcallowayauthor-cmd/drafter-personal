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
    // The `private(set)`/`private` access these carried when the whole implementation
    // lived in one file has been relaxed to plain internal (still get+set within this
    // module only) so `attach`, GitHub-sync, concurrent-editing, and binder-operation
    // code can live in their own `ProjectViewModel+*.swift` extensions — see
    // [[ProjectViewModel+Attach]], [[ProjectViewModel+GitHubSync]],
    // [[ProjectViewModel+ConcurrentEditing]], [[ProjectViewModel+BinderOperations]].
    var metadata: ProjectMetadata?
    var binderTree: BinderTree?
    var errorMessage: String?
    var autocommitScheduler: AutocommitScheduler?
    /// `nil` for a local-only project (no `origin` remote configured) — §5.5's sync
    /// loop has nothing to do without a remote, so it's simply never started rather
    /// than running and failing every pass.
    var syncScheduler: SyncScheduler?
    /// Shared with `HistoryViewModel` (§5.8) so it isn't standing up a second actor
    /// against the same working tree. `nil` for a Local-file-mode project.
    var gitService: GitService?
    /// Local-file mode's counterpart to `gitService`, §7.
    var snapshotService: SnapshotService?
    var snapshotCoordinator: SnapshotCoordinator?
    /// Whichever of `gitService`/`snapshotService` is live for the open project — what
    /// `HistoryViewModel` (§9.1) actually needs, without caring which mode it is.
    var versioningSource: (any VersioningSource)?
    var workingTreeRoot: URL?
    /// Non-fatal: set after `createNewProject` regardless of whether GitHub connection
    /// succeeded. §5.2 — a project that failed to connect is still fully usable
    /// locally, so this never blocks `metadata`/`binderTree` from being populated.
    var syncStatusMessage: String?
    /// §6.4's no-lock-file concurrent-editing check — set on open and on focus regain.
    var concurrentEditingWarning: ConcurrentEditingWarning.Info?

    /// §6.3: called (already debounced, on the main actor) whenever the working tree
    /// changes on disk from outside the app. `ContentView` sets this to refresh the
    /// binder and apply the open-scene reload rules; `ProjectViewModel` itself only
    /// owns the watcher's lifecycle, not what "reload" means for an open editor.
    var onExternalChange: ((Set<URL>) -> Void)?

    var project: Project?
    var fileSystemWatcher: FileSystemWatcher?
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
    let registeredRootBox = RegisteredRootBox()
    var registeredRoot: URL? {
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
    var operationQueue: Task<Void, Never> = Task {}

    func serialized(_ operation: @escaping () async -> Void) async {
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
            await Self.seedFrontBackMatter(metadata: metadata, root: root, project: project)

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

    /// §9.2: seed the standard Front/Back Matter files at creation so a new project
    /// opens with a title page, copyright page, etc. already in place. `generateMissing`
    /// is additive — the "Generate Front/Back Matter" menu item and "Regenerate from
    /// Template" (which re-pulls updated metadata) both still work exactly as before.
    private static func seedFrontBackMatter(metadata: ProjectMetadata, root: URL, project: Project) async {
        _ = try? FrontBackMatterService.generateMissing(
            metadata: metadata,
            workingTree: root,
            fileWriter: LiveAtomicFileWriter()
        )
        try? await project.refreshBinderTree()
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
    /// (§5.2: "Slugify the title → `last-call`").
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
}

/// See `ProjectViewModel.registeredRoot`'s doc comment.
final class RegisteredRootBox: @unchecked Sendable {
    nonisolated(unsafe) var value: URL?
}
