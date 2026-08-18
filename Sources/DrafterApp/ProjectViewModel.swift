import DrafterCore
import Foundation
import GitService
import Observation
import ProjectStore

/// Opens a project folder and exposes a read-only snapshot for `ContentView`'s binder
/// list, plus the M2 git wiring (§7): a repo is initialized in-place if missing, and
/// `autocommitScheduler` is exposed so the editor can report activity into it.
@MainActor
@Observable
final class ProjectViewModel {
    private(set) var metadata: ProjectMetadata?
    private(set) var binderTree: BinderTree?
    private(set) var errorMessage: String?
    private(set) var autocommitScheduler: AutocommitScheduler?
    /// Shared with `HistoryViewModel` (§5.8) so it isn't standing up a second actor
    /// against the same working tree.
    private(set) var gitService: GitService?
    private(set) var workingTreeRoot: URL?

    private var project: Project?

    func open(root: URL) async {
        errorMessage = nil
        do {
            let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
            self.project = project
            let metadata = await project.metadata
            self.metadata = metadata
            binderTree = await project.binderTree
            workingTreeRoot = root

            let gitService = GitService(processRunner: LiveProcessRunner())
            self.gitService = gitService
            let repositoryCoordinator = RepositoryCoordinator(gitService: gitService, workingTree: root)
            try await repositoryCoordinator.ensureInitialized(authorName: metadata.author)
            autocommitScheduler = AutocommitScheduler(repositoryCoordinator: repositoryCoordinator)
        } catch {
            self.project = nil
            metadata = nil
            binderTree = nil
            autocommitScheduler = nil
            gitService = nil
            workingTreeRoot = nil
            errorMessage = String(describing: error)
        }
    }

    func refresh() async {
        guard let project else { return }
        do {
            try await project.refreshBinderTree()
            binderTree = await project.binderTree
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
