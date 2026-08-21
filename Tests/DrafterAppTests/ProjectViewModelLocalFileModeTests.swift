import DrafterCore
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

/// §5/§7: Local-file mode's project-creation and reopen path — no git, no network, so
/// unlike Git mode's `createNewProject` this is safe to exercise end to end.
@Suite("ProjectViewModel Local-file mode", .serialized)
@MainActor
struct ProjectViewModelLocalFileModeTests {
    @Test("creating a Local-file project skips git entirely and takes an initial snapshot")
    func createsLocalFileProject() async throws {
        let location = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: location) }

        let viewModel = ProjectViewModel()
        await viewModel.createNewProject(
            title: "The Last Shift",
            author: "Tim Fleet",
            location: location,
            versionControl: .localFile
        )

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.metadata?.versionControl == .localFile)
        #expect(viewModel.gitService == nil)
        #expect(viewModel.snapshotService != nil)
        #expect(viewModel.versioningSource != nil)

        let root = location.appendingPathComponent("the-last-shift")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path))
        let history = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("History").path)
        #expect(history.count == 1)

        await viewModel.closeProject()
    }

    @Test("a Local-file project reopens with its mode intact and no git wiring")
    func reopensPreservingMode() async throws {
        let location = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: location) }

        let creator = ProjectViewModel()
        await creator.createNewProject(title: "Cloud Book", author: "Tim Fleet", location: location, versionControl: .localFile)
        #expect(creator.errorMessage == nil)
        let root = location.appendingPathComponent("cloud-book")
        await creator.closeProject()

        let reopener = ProjectViewModel()
        await reopener.open(root: root)

        #expect(reopener.errorMessage == nil)
        #expect(reopener.metadata?.versionControl == .localFile)
        #expect(reopener.gitService == nil)
        #expect(reopener.versioningSource != nil)

        await reopener.closeProject()
    }

    @Test("Short Story preset sets bare-number chapterTitleFormat; Novel keeps 'Chapter {n}'")
    func manuscriptTemplateSetsChapterTitleFormat() async throws {
        let location = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: location) }

        let shortStory = ProjectViewModel()
        await shortStory.createNewProject(
            title: "Sunrise At Sundown",
            author: "Drew Calloway",
            location: location,
            versionControl: .localFile,
            manuscriptTemplate: .shortStory
        )
        #expect(shortStory.errorMessage == nil)
        #expect(shortStory.metadata?.compile.chapterTitleFormat == "{n}")
        await shortStory.closeProject()

        let novel = ProjectViewModel()
        await novel.createNewProject(
            title: "Rook Takes",
            author: "Drew Calloway",
            location: location,
            versionControl: .localFile,
            manuscriptTemplate: .novel
        )
        #expect(novel.errorMessage == nil)
        #expect(novel.metadata?.compile.chapterTitleFormat == "Chapter {n}")
        await novel.closeProject()
    }

    @Test("setCoverImage then removeCoverImage round-trips: file appears, then disappears")
    func setThenRemoveCoverImage() async throws {
        let location = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: location) }

        let viewModel = ProjectViewModel()
        await viewModel.createNewProject(
            title: "Cover Test",
            author: "Tim Fleet",
            location: location,
            versionControl: .localFile
        )
        #expect(viewModel.errorMessage == nil)

        let sourceURL = location.appendingPathComponent("cover-source.png")
        try Data("png bytes".utf8).write(to: sourceURL)

        let didSet = await viewModel.setCoverImage(from: sourceURL)
        #expect(didSet)
        #expect(viewModel.metadata?.compile.coverImage == "Resources/cover.png")
        let coverURL = viewModel.workingTreeRoot!.appendingPathComponent("Resources/cover.png")
        #expect(FileManager.default.fileExists(atPath: coverURL.path))

        await viewModel.removeCoverImage()
        #expect(!FileManager.default.fileExists(atPath: coverURL.path))

        await viewModel.closeProject()
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
