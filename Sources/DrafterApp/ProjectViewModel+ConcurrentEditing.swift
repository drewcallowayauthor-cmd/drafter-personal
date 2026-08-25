import DrafterCore
import GitService
import SnapshotService

/// §6.4/§8.3's no-lock-file concurrent-editing check, split out to keep
/// `ProjectViewModel`'s file/type-body lengths under SwiftLint's limits.
extension ProjectViewModel {
    /// Called on project open (via `attach`) and again whenever the window regains
    /// focus. Dispatches on the open project's mode — Git mode checks `origin/main`,
    /// Local-file mode checks `History/`.
    func checkConcurrentEditing() async {
        switch metadata?.versionControl {
        case .git: await checkConcurrentEditingGit()
        case .localFile: await checkConcurrentEditingLocalFile()
        case nil: return
        }
    }

    func checkConcurrentEditingGit() async {
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

    func checkConcurrentEditingLocalFile() async {
        guard let snapshotService, let workingTreeRoot else { return }
        concurrentEditingWarning = await ConcurrentEditingWarning.checkLocalFile(
            snapshotService: snapshotService,
            workingTree: workingTreeRoot,
            ownMachineName: RepositoryCoordinator.defaultMachineName()
        )
    }
}
