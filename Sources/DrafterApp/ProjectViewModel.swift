import DrafterCore
import Foundation
import Observation
import ProjectStore

/// M0 placeholder view model: opens a project folder and exposes a read-only snapshot
/// for `ContentView`'s binder list. Write operations (save, resequence, …) come later
/// milestones — this only proves the ProjectStore wiring end to end.
@MainActor
@Observable
final class ProjectViewModel {
    private(set) var metadata: ProjectMetadata?
    private(set) var binderTree: BinderTree?
    private(set) var errorMessage: String?

    private var project: Project?

    func open(root: URL) async {
        errorMessage = nil
        do {
            let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
            self.project = project
            metadata = await project.metadata
            binderTree = await project.binderTree
        } catch {
            self.project = nil
            metadata = nil
            binderTree = nil
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
