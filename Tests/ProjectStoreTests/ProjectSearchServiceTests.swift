import DrafterCore
import Foundation
import Testing
@testable import ProjectStore

@Suite("ProjectSearchService")
struct ProjectSearchServiceTests {
    @Test("search finds matches across chapters and reports scene/offset")
    func searchFindsMatchesAcrossChapters() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try BinderTreeBuilder.build(projectRoot: root)

        let matches = ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "lantern"))

        #expect(matches.count == 2)
        #expect(Set(matches.map(\.sceneDisplayName)) == ["Triage", "Second Scene"])
        for match in matches {
            let document = try SceneDocument.load(from: match.sceneURL)
            let nsBody = document.body as NSString
            #expect(nsBody.substring(with: match.range).lowercased() == "lantern")
        }
    }

    @Test("search is case-insensitive by default and honors caseSensitive")
    func searchCaseSensitivity() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try BinderTreeBuilder.build(projectRoot: root)

        let insensitive = ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "Lantern"))
        #expect(insensitive.count == 2)

        // Only "Second Scene" capitalizes "Lantern" (start of its sentence); "Triage"'s
        // is lowercase, so the case-sensitive search finds just the one.
        let sensitive = ProjectSearchService.search(
            binderTree: tree,
            options: ProjectSearchOptions(query: "Lantern", caseSensitive: true)
        )
        #expect(sensitive.count == 1)
    }

    @Test("matchWholeWord excludes substring matches inside other words")
    func searchWholeWord() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try BinderTreeBuilder.build(projectRoot: root)

        // "lit" appears once as its own word ("She lit the...") and once as a substring
        // of "split" ("split-rail") — the non-whole-word search finds both.
        let partial = ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "lit"))
        #expect(partial.count == 2)

        let wholeWord = ProjectSearchService.search(
            binderTree: tree,
            options: ProjectSearchOptions(query: "lit", matchWholeWord: true)
        )
        #expect(wholeWord.count == 1)
    }

    @Test("replace rewrites every matched scene on disk and leaves other text untouched")
    func replaceRewritesMatchedScenes() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try BinderTreeBuilder.build(projectRoot: root)
        let matches = ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "lantern"))

        let rewrittenURLs = try ProjectSearchService.replace(
            matches: matches,
            replacement: "torch",
            fileWriter: LiveAtomicFileWriter()
        )

        #expect(rewrittenURLs.count == 2)
        for url in rewrittenURLs {
            let document = try SceneDocument.load(from: url)
            #expect(!document.body.lowercased().contains("lantern"))
            #expect(document.body.contains("torch"))
        }

        let refreshedTree = try BinderTreeBuilder.build(projectRoot: root)
        #expect(ProjectSearchService.search(binderTree: refreshedTree, options: ProjectSearchOptions(query: "lantern")).isEmpty)
    }

    @Test("replace rewrites multiple matches in the same file without offset drift")
    func replaceHandlesMultipleMatchesInOneFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        let sceneURL = chapterDirectory.appendingPathComponent("01 Triage.md")
        try Data("She lit a lantern, then a second lantern, in the lantern-lit hall.".utf8).write(to: sceneURL)

        let tree = try BinderTreeBuilder.build(projectRoot: root)
        let matches = ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "lantern"))
        #expect(matches.count == 3)

        try ProjectSearchService.replace(matches: matches, replacement: "candle", fileWriter: LiveAtomicFileWriter())

        let document = try SceneDocument.load(from: sceneURL)
        #expect(document.body == "She lit a candle, then a second candle, in the candle-lit hall.")
    }

    @Test("search returns nothing for an empty query")
    func searchEmptyQueryReturnsNothing() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try BinderTreeBuilder.build(projectRoot: root)

        #expect(ProjectSearchService.search(binderTree: tree, options: ProjectSearchOptions(query: "")).isEmpty)
    }

    /// Two chapters, one scene each, both mentioning "lantern" once — "Triage" also has
    /// a "lit" that isn't a whole word ("lantern-lit" isn't in this fixture, but "split"
    /// is, to exercise `matchWholeWord`).
    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstChapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try FileManager.default.createDirectory(at: firstChapterDirectory, withIntermediateDirectories: true)
        try Data("She lit the split-rail fence with a lantern.".utf8)
            .write(to: firstChapterDirectory.appendingPathComponent("01 Triage.md"))

        let secondChapterDirectory = root.appendingPathComponent("Manuscript/02 Second Chapter")
        try FileManager.default.createDirectory(at: secondChapterDirectory, withIntermediateDirectories: true)
        try Data("Another Lantern hung by the door.".utf8)
            .write(to: secondChapterDirectory.appendingPathComponent("01 Second Scene.md"))

        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)
        let store = ProjectMetadataStore(fileWriter: LiveAtomicFileWriter())
        try store.save(metadata, to: root)

        return root
    }
}
