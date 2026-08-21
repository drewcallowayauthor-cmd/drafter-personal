import DrafterCore
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

@Suite("FrontBackMatterService")
struct FrontBackMatterServiceTests {
    private let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

    @Test("generateMissing writes all six standard files to a fresh project")
    func generateMissingWritesAllSixFiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let created = try FrontBackMatterService.generateMissing(
            metadata: metadata,
            workingTree: root,
            fileWriter: LiveAtomicFileWriter()
        )

        #expect(created.count == 6)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("FrontMatter/01 Title Page.md").path))
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("BackMatter/03 About the Author.md").path)
        )
    }

    @Test("generateMissing leaves an existing file untouched, even if hand-edited")
    func generateMissingLeavesExistingFileUntouched() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let titlePageURL = root.appendingPathComponent("FrontMatter/01 Title Page.md")
        try FileManager.default.createDirectory(at: titlePageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Hand-edited content.".utf8).write(to: titlePageURL)

        let created = try FrontBackMatterService.generateMissing(
            metadata: metadata,
            workingTree: root,
            fileWriter: LiveAtomicFileWriter()
        )

        #expect(created.contains(titlePageURL) == false)
        #expect(try String(contentsOf: titlePageURL, encoding: .utf8) == "Hand-edited content.")
    }

    @Test("regenerate overwrites a file with fresh template content")
    func regenerateOverwritesFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let titlePageURL = root.appendingPathComponent("FrontMatter/01 Title Page.md")
        try FileManager.default.createDirectory(at: titlePageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Stale hand-edited content.".utf8).write(to: titlePageURL)

        try FrontBackMatterService.regenerate(
            template: .titlePage,
            metadata: metadata,
            workingTree: root,
            fileWriter: LiveAtomicFileWriter()
        )

        let content = try String(contentsOf: titlePageURL, encoding: .utf8)
        #expect(content == FrontBackMatterTemplate.titlePage.content(for: metadata))
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
