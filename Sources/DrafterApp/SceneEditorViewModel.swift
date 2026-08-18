import Foundation
import Observation
import ProjectStore

/// Owns the currently open scene in the editor pane. Loading is separate from
/// `ProjectViewModel`'s project-level state since which scene is open changes far more
/// often than which project is.
@MainActor
@Observable
final class SceneEditorViewModel {
    private(set) var document: SceneDocument?
    private(set) var errorMessage: String?

    func open(url: URL) {
        errorMessage = nil
        do {
            document = try SceneDocument.load(from: url)
        } catch {
            document = nil
            errorMessage = String(describing: error)
        }
    }

    func close() {
        document = nil
        errorMessage = nil
    }

    func updateBody(_ body: String) {
        document?.body = body
    }
}
