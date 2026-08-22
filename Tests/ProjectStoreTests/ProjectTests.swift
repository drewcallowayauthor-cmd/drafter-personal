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

        #expect(metadata.title == "Last Call")
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

    @Test("create scaffolds the standard folders, writes project.json, .gitignore, and .gitattributes")
    func createScaffoldsNewProject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = ProjectMetadata(title: "New Book", author: "Drew Calloway", copyrightYear: 2026)

        let project = try Project.create(root: root, metadata: metadata, fileWriter: LiveAtomicFileWriter())

        #expect(await project.metadata.title == "New Book")
        for subdirectory in ["Manuscript", "FrontMatter", "BackMatter", "Notes", "Resources"] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(subdirectory).path,
                isDirectory: &isDirectory
            )
            #expect(exists && isDirectory.boolValue)
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("project.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitignore").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitattributes").path))

        let reopened = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        #expect(await reopened.metadata.title == "New Book")
    }

    @Test("create refuses to scaffold over an existing folder")
    func createRefusesExistingFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = ProjectMetadata(title: "New Book", author: "Drew Calloway", copyrightYear: 2026)

        #expect(throws: DrafterError.self) {
            try Project.create(root: root, metadata: metadata, fileWriter: LiveAtomicFileWriter())
        }
    }

    @Test("createChapter adds a new chapter folder seeded with one scene, and refreshes the tree")
    func createChapterAddsSeededChapter() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())

        let sceneURL = try await project.createChapter(title: "The First Hour", fileWriter: LiveAtomicFileWriter())

        #expect(sceneURL.lastPathComponent == "01 New Scene.md")
        #expect(sceneURL.deletingLastPathComponent().lastPathComponent == "02 The First Hour")
        #expect(FileManager.default.fileExists(atPath: sceneURL.path))

        let tree = await project.binderTree
        #expect(tree.manuscript.map(\.displayName) == ["Arrival", "The First Hour"])
        #expect(tree.manuscript[1].scenes.map(\.displayName) == ["New Scene"])
    }

    @Test("createScene adds the next-numbered scene to an existing chapter")
    func createSceneAddsToExistingChapter() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")

        let sceneURL = try await project.createScene(title: "The Board", in: chapterDirectory, fileWriter: LiveAtomicFileWriter())

        #expect(sceneURL.lastPathComponent == "02 The Board.md")
        let contents = try String(contentsOf: sceneURL, encoding: .utf8)
        #expect(contents.contains("status: draft"))

        let tree = await project.binderTree
        #expect(tree.manuscript[0].scenes.map(\.displayName) == ["Triage", "The Board"])
    }

    @Test("rename keeps the numeric prefix and only replaces the display name")
    func renameKeepsPrefix() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let sceneURL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")

        let newURL = try await project.rename(itemAt: sceneURL, to: "Sorting")

        #expect(newURL.lastPathComponent == "01 Sorting.md")
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(!FileManager.default.fileExists(atPath: sceneURL.path))
        #expect(await project.binderTree.manuscript[0].scenes.map(\.displayName) == ["Sorting"])
    }

    @Test("rename sanitizes illegal filename characters in the new title")
    func renameSanitizesTitle() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let chapterURL = root.appendingPathComponent("Manuscript/01 Arrival")

        let newURL = try await project.rename(itemAt: chapterURL, to: "Before: After")

        #expect(newURL.lastPathComponent == "01 Before- After")
    }

    @Test("delete removes a scene file and refreshes the tree")
    func deleteRemovesScene() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let sceneURL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")

        try await project.delete(itemAt: sceneURL)

        #expect(!FileManager.default.fileExists(atPath: sceneURL.path))
        #expect(await project.binderTree.manuscript[0].scenes.isEmpty)
    }

    @Test("delete moves the item to the Trash rather than permanently unlinking it")
    func deleteMovesToTrashNotPermanentlyUnlinked() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let sceneURL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")

        let trashedURL = try await project.delete(itemAt: sceneURL)

        #expect(!FileManager.default.fileExists(atPath: sceneURL.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        try? FileManager.default.removeItem(at: trashedURL)
    }

    @Test("delete removes an entire chapter folder with its scenes")
    func deleteRemovesChapter() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let chapterURL = root.appendingPathComponent("Manuscript/01 Arrival")

        try await project.delete(itemAt: chapterURL)

        #expect(!FileManager.default.fileExists(atPath: chapterURL.path))
        #expect(await project.binderTree.manuscript.isEmpty)
    }

    @Test("reorder resequences prefixes to match the caller's order, even with a swap")
    func reorderResequencesPrefixes() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        let secondSceneURL = try await project.createScene(
            title: "The Board",
            in: chapterDirectory,
            fileWriter: LiveAtomicFileWriter()
        )
        let firstSceneURL = chapterDirectory.appendingPathComponent("01 Triage.md")

        try await project.reorder(orderedURLs: [secondSceneURL, firstSceneURL])

        let tree = await project.binderTree
        #expect(tree.manuscript[0].scenes.map(\.displayName) == ["The Board", "Triage"])
        #expect(FileManager.default.fileExists(atPath: chapterDirectory.appendingPathComponent("01 The Board.md").path))
        #expect(FileManager.default.fileExists(atPath: chapterDirectory.appendingPathComponent("02 Triage.md").path))
    }

    @Test("moveScene moves a scene into a different chapter, resequencing both directories")
    func moveSceneCrossChapter() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let sourceChapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        let secondSceneURL = try await project.createScene(
            title: "The Board",
            in: sourceChapterDirectory,
            fileWriter: LiveAtomicFileWriter()
        )
        let destinationChapterURL = try await project.createChapter(
            title: "Second Chapter",
            fileWriter: LiveAtomicFileWriter()
        ).deletingLastPathComponent()

        try await project.moveScene(at: secondSceneURL, toChapterDirectory: destinationChapterURL, before: nil)

        let tree = await project.binderTree
        #expect(tree.manuscript[0].scenes.map(\.displayName) == ["Triage"])
        #expect(tree.manuscript[1].scenes.map(\.displayName) == ["New Scene", "The Board"])
        #expect(!FileManager.default.fileExists(atPath: secondSceneURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: destinationChapterURL.appendingPathComponent("02 The Board.md").path
            )
        )
    }

    @Test("moveScene reorders within the same chapter when the destination directory is unchanged")
    func moveSceneSameChapterReorder() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        let secondSceneURL = try await project.createScene(
            title: "The Board",
            in: chapterDirectory,
            fileWriter: LiveAtomicFileWriter()
        )
        let firstSceneURL = chapterDirectory.appendingPathComponent("01 Triage.md")

        try await project.moveScene(at: secondSceneURL, toChapterDirectory: chapterDirectory, before: firstSceneURL)

        let tree = await project.binderTree
        #expect(tree.manuscript[0].scenes.map(\.displayName) == ["The Board", "Triage"])
    }

    @Test("importFile copies an external file into a directory with the next prefix, preserving its extension")
    func importFileCopiesExternalFile() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())
        let notesDirectory = root.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("cast list.pdf")
        try Data("pdf bytes".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let importedURL = try await project.importFile(from: sourceURL, into: notesDirectory)

        #expect(importedURL.lastPathComponent == "01 cast list.pdf")
        #expect(FileManager.default.fileExists(atPath: importedURL.path))
        #expect(await project.binderTree.notes.map(\.displayName) == ["cast list"])
    }

    @Test("setCoverImage copies the image into Resources/ and updates compile.coverImage")
    func setCoverImageCopiesAndUpdatesMetadata() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("art.png")
        try Data("png bytes".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let coverURL = try await project.setCoverImage(from: sourceURL, fileWriter: LiveAtomicFileWriter())

        #expect(coverURL.lastPathComponent == "cover.png")
        #expect(FileManager.default.fileExists(atPath: coverURL.path))
        #expect(await project.metadata.compile.coverImage == "Resources/cover.png")
    }

    @Test("setCoverImage replaces a previous cover file with a different extension")
    func setCoverImageReplacesPreviousCover() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project.open(root: root, fileWriter: LiveAtomicFileWriter())

        let firstSourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("first.jpg")
        try Data("jpg bytes".utf8).write(to: firstSourceURL)
        defer { try? FileManager.default.removeItem(at: firstSourceURL) }
        let firstCoverURL = try await project.setCoverImage(from: firstSourceURL, fileWriter: LiveAtomicFileWriter())

        let secondSourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("second.png")
        try Data("png bytes".utf8).write(to: secondSourceURL)
        defer { try? FileManager.default.removeItem(at: secondSourceURL) }
        let secondCoverURL = try await project.setCoverImage(from: secondSourceURL, fileWriter: LiveAtomicFileWriter())

        #expect(!FileManager.default.fileExists(atPath: firstCoverURL.path))
        #expect(FileManager.default.fileExists(atPath: secondCoverURL.path))
        #expect(await project.metadata.compile.coverImage == "Resources/cover.png")
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        try Data("Text.".utf8).write(to: chapterDirectory.appendingPathComponent("01 Triage.md"))

        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)
        let store = ProjectMetadataStore(fileWriter: LiveAtomicFileWriter())
        try store.save(metadata, to: root)

        return root
    }
}
