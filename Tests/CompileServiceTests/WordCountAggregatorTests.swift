import Foundation
import ProjectStore
import Testing
@testable import CompileService

@Suite("WordCountAggregator")
struct WordCountAggregatorTests {
    @Test("sums word counts per chapter and across the project")
    func sumsPerChapterAndProject() throws {
        let scene1 = url("Manuscript/01 Arrival/01 Triage.md")
        let scene2 = url("Manuscript/01 Arrival/02 The Board.md")
        let scene3 = url("Manuscript/02 The First Hour/01 Handoff.md")
        let chapter1 = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [
                SceneNode(url: scene1, displayName: "Triage"),
                SceneNode(url: scene2, displayName: "The Board")
            ],
            isLooseFile: false
        )
        let chapter2 = ChapterNode(
            url: url("Manuscript/02 The First Hour"),
            displayName: "The First Hour",
            scenes: [SceneNode(url: scene3, displayName: "Handoff")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter1, chapter2], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            scene1: scene("One two three."),
            scene2: scene("Four five."),
            scene3: scene("Six seven eight nine.")
        ]

        let totals = try WordCountAggregator.aggregate(binderTree: tree, read: { contents[$0]! })

        #expect(totals.perChapter.count == 2)
        #expect(totals.perChapter[0] == ChapterWordCount(chapter: "Arrival", words: 5))
        #expect(totals.perChapter[1] == ChapterWordCount(chapter: "The First Hour", words: 4))
        #expect(totals.project == 9)
    }

    @Test("counts scenes marked compile: false too, unlike ManuscriptAssembler")
    func countsExcludedScenesToo() throws {
        let sceneURL = url("Manuscript/01 Arrival/01 Cut Scene.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Cut Scene")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [sceneURL: scene("Five whole words right here.", compile: false)]

        let totals = try WordCountAggregator.aggregate(binderTree: tree, read: { contents[$0]! })

        #expect(totals.project == 5)
    }

    @Test("a loose-file chapter counts as its own single-scene chapter")
    func looseFileChapterCounts() throws {
        let looseURL = url("Manuscript/02 Interlude.md")
        let chapter = ChapterNode(url: looseURL, displayName: "Interlude", scenes: [], isLooseFile: true)
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [looseURL: scene("Two words.")]

        let totals = try WordCountAggregator.aggregate(binderTree: tree, read: { contents[$0]! })

        #expect(totals.perChapter == [ChapterWordCount(chapter: "Interlude", words: 2)])
        #expect(totals.project == 2)
    }

    @Test("an empty manuscript aggregates to zero")
    func emptyManuscriptAggregatesToZero() throws {
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let totals = try WordCountAggregator.aggregate(binderTree: tree, read: { _ in "" })

        #expect(totals.project == 0)
        #expect(totals.perChapter.isEmpty)
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: "/tmp/fixture/\(path)")
    }

    private func scene(_ body: String, compile: Bool = true) -> String {
        """
        ---
        synopsis:
        status: draft
        compile: \(compile)
        notes:
        ---

        \(body)
        """
    }
}
