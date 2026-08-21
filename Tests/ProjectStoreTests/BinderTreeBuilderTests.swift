import Foundation
import Testing
@testable import ProjectStore

@Suite("BinderTreeBuilder")
struct BinderTreeBuilderTests {
    @Test("builds the design doc's example layout: chapters, a loose-file chapter, and flat sections")
    func buildsDesignDocLayout() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "01 Arrival",
            files: ["01 Triage.md", "02 The Board.md", "03 Room Nine.md"],
            under: root.appendingPathComponent("Manuscript")
        )
        try write(
            "02 The First Hour",
            files: ["01 Handoff.md", "02 Code Blue.md"],
            under: root.appendingPathComponent("Manuscript")
        )
        try writeLooseFile("03 Interlude.md", under: root.appendingPathComponent("Manuscript"))

        try writeFlatSection(
            "FrontMatter",
            files: ["02 Title Page.md", "01 Also By.md", "03 Copyright.md", "04 Dedication.md"],
            under: root
        )
        try writeFlatSection("BackMatter", files: ["01 About the Author.md", "02 Newsletter.md"], under: root)
        try writeFlatSection("Notes", files: ["outline.md"], under: root)

        let tree = try BinderTreeBuilder.build(projectRoot: root)

        #expect(tree.manuscript.map(\.displayName) == ["Arrival", "The First Hour", "Interlude"])
        #expect(tree.manuscript[0].scenes.map(\.displayName) == ["Triage", "The Board", "Room Nine"])
        #expect(tree.manuscript[1].scenes.map(\.displayName) == ["Handoff", "Code Blue"])
        #expect(tree.manuscript[0].isLooseFile == false)
        #expect(tree.manuscript[2].isLooseFile == true)
        #expect(tree.manuscript[2].scenes.isEmpty)

        #expect(tree.frontMatter.map(\.displayName) == ["Also By", "Title Page", "Copyright", "Dedication"])
        #expect(tree.backMatter.map(\.displayName) == ["About the Author", "Newsletter"])
        #expect(tree.notes.map(\.displayName) == ["outline"])
    }

    @Test("tolerates missing optional sections instead of throwing")
    func toleratesMissingSections() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("01 Arrival", files: ["01 Triage.md"], under: root.appendingPathComponent("Manuscript"))
        // No FrontMatter/, BackMatter/, or Notes/ created.

        let tree = try BinderTreeBuilder.build(projectRoot: root)

        #expect(tree.manuscript.map(\.displayName) == ["Arrival"])
        #expect(tree.frontMatter.isEmpty)
        #expect(tree.backMatter.isEmpty)
        #expect(tree.notes.isEmpty)
    }

    @Test("ignores non-markdown files like .DS_Store")
    func ignoresNonMarkdownFiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manuscript = root.appendingPathComponent("Manuscript")
        try write("01 Arrival", files: ["01 Triage.md"], under: manuscript)
        try Data().write(to: manuscript.appendingPathComponent(".DS_Store"))

        let tree = try BinderTreeBuilder.build(projectRoot: root)

        #expect(tree.manuscript.map(\.displayName) == ["Arrival"])
    }

    @Test("Notes accepts any file type, unlike Front/Back Matter's markdown-only filter")
    func notesAcceptsNonMarkdownFiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFlatSection("Notes", files: ["01 outline.md", "02 cast list.pdf", "03 map.png"], under: root)
        try writeFlatSection("FrontMatter", files: ["01 Title Page.md", "02 reference.pdf"], under: root)

        let tree = try BinderTreeBuilder.build(projectRoot: root)

        #expect(tree.notes.map(\.displayName) == ["outline", "cast list", "map"])
        // Front Matter stays markdown-only even when a non-`.md` file sneaks in.
        #expect(tree.frontMatter.map(\.displayName) == ["Title Page"])
    }

    private func write(_ chapterName: String, files: [String], under manuscriptDirectory: URL) throws {
        let chapterDirectory = manuscriptDirectory.appendingPathComponent(chapterName)
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        for file in files {
            try Data("---\nstatus: draft\n---\n\nText.".utf8)
                .write(to: chapterDirectory.appendingPathComponent(file))
        }
    }

    private func writeLooseFile(_ name: String, under manuscriptDirectory: URL) throws {
        try FileManager.default.createDirectory(at: manuscriptDirectory, withIntermediateDirectories: true)
        try Data("Text.".utf8).write(to: manuscriptDirectory.appendingPathComponent(name))
    }

    private func writeFlatSection(_ sectionName: String, files: [String], under root: URL) throws {
        let directory = root.appendingPathComponent(sectionName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try Data("Text.".utf8).write(to: directory.appendingPathComponent(file))
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
