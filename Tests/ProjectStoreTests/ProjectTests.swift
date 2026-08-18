import DrafterCore
import Foundation
import Testing
@testable import ProjectStore

@Suite("Project")
struct ProjectTests {
    @Test("open loads metadata and builds the binder tree from disk")
    func openLoadsMetadataAndTree() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())

        let metadata = await project.metadata
        let tree = await project.binderTree

        #expect(metadata.title == "The Last Shift")
        #expect(tree.manuscript.map(\.displayName) == ["Arrival"])
    }

    @Test("refreshBinderTree picks up files added after open")
    func refreshPicksUpNewFiles() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        #expect(await project.binderTree.manuscript[0].scenes.count == 1)

        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try Data("Text.".utf8).write(to: chapterDirectory.appendingPathComponent("02 Second Scene.md"))

        try await project.refreshBinderTree()

        #expect(await project.binderTree.manuscript[0].scenes.count == 2)
    }

    @Test("save persists metadata to disk and updates in-memory state")
    func savePersistsAndUpdates() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        var updated = await project.metadata
        updated.title = "New Title"

        try await project.save(metadata: updated)

        #expect(await project.metadata.title == "New Title")

        let reloaded = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        #expect(await reloaded.metadata.title == "New Title")
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        try Data("Text.".utf8).write(to: chapterDirectory.appendingPathComponent("01 Triage.md"))

        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let store = ProjectMetadataStore(fileWriter: LiveAtomicFileWriter())
        try store.save(metadata, to: root)

        return root
    }
}
