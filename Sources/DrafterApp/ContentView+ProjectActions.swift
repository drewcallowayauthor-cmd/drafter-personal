import DrafterCore
import Foundation
import ProjectStore

extension ContentView {
    func generateMissingFrontBackMatter() {
        guard let metadata = projectViewModel.metadata, let root = projectViewModel.workingTreeRoot else { return }
        do {
            _ = try FrontBackMatterService.generateMissing(
                metadata: metadata,
                workingTree: root,
                fileWriter: LiveAtomicFileWriter()
            )
            Task { await projectViewModel.refresh() }
        } catch {
            frontBackMatterError = error.localizedDescription
        }
    }

    func performRegenerate() {
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

    func isOpenableScene(_ url: URL) -> Bool {
        guard let tree = projectViewModel.binderTree else { return false }
        let inManuscript = tree.manuscript.contains { chapter in
            (chapter.isLooseFile && chapter.url == url) || chapter.scenes.contains { $0.url == url }
        }
        return inManuscript
            || tree.frontMatter.contains { $0.url == url }
            || tree.backMatter.contains { $0.url == url }
            || tree.notes.contains { $0.url == url }
    }
}
