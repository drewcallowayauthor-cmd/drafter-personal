import Foundation
import ProjectStore
import Testing
@testable import CompileService

@Suite("ManuscriptAssembler")
struct ManuscriptAssemblerTests {
    private let compile = ProjectMetadata.Compile()

    @Test("emits a heading per chapter and joins scenes with the separator")
    func emitsHeadingsAndJoinsScenes() throws {
        let scene1 = url("Manuscript/01 Arrival/01 Triage.md")
        let scene2 = url("Manuscript/01 Arrival/02 The Board.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [
                SceneNode(url: scene1, displayName: "Triage"),
                SceneNode(url: scene2, displayName: "The Board")
            ],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            scene1: scene("First scene text."),
            scene2: scene("Second scene text.")
        ]

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: compile,
            read: { contents[$0]! }
        )

        #expect(assembled == "Chapter 1\n\nFirst scene text.\n\n* * *\n\nSecond scene text.")
    }

    @Test("a loose file at Manuscript root becomes its own single-scene chapter")
    func looseFileBecomesOwnChapter() throws {
        let looseURL = url("Manuscript/02 Interlude.md")
        let chapter = ChapterNode(url: looseURL, displayName: "Interlude", scenes: [], isLooseFile: true)
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [looseURL: scene("Interlude text.")]

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: compile,
            read: { contents[$0]! }
        )

        #expect(assembled == "Chapter 1\n\nInterlude text.")
    }

    @Test("scenes marked compile: false are excluded")
    func excludesNonCompilingScenes() throws {
        let included = url("Manuscript/01 Arrival/01 Triage.md")
        let excluded = url("Manuscript/01 Arrival/02 Cut Scene.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [
                SceneNode(url: included, displayName: "Triage"),
                SceneNode(url: excluded, displayName: "Cut Scene")
            ],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            included: scene("Kept."),
            excluded: scene("Dropped.", compile: false)
        ]

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: compile,
            read: { contents[$0]! }
        )

        #expect(assembled == "Chapter 1\n\nKept.")
    }

    @Test("a chapter whose every scene is excluded is dropped and doesn't consume a chapter number")
    func dropsFullyExcludedChapterAndRenumbers() throws {
        let droppedScene = url("Manuscript/01 Cut Chapter/01 Only Scene.md")
        let keptScene = url("Manuscript/02 Arrival/01 Triage.md")
        let droppedChapter = ChapterNode(
            url: url("Manuscript/01 Cut Chapter"),
            displayName: "Cut Chapter",
            scenes: [SceneNode(url: droppedScene, displayName: "Only Scene")],
            isLooseFile: false
        )
        let keptChapter = ChapterNode(
            url: url("Manuscript/02 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: keptScene, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [droppedChapter, keptChapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            droppedScene: scene("Dropped.", compile: false),
            keptScene: scene("Kept.")
        ]

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: compile,
            read: { contents[$0]! }
        )

        #expect(assembled == "Chapter 1\n\nKept.")
    }

    @Test("chapterTitleFormat 'none' emits no heading")
    func noneFormatEmitsNoHeading() throws {
        let sceneURL = url("Manuscript/01 Arrival/01 Triage.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [sceneURL: scene("Text.")]
        var noHeadingCompile = ProjectMetadata.Compile()
        noHeadingCompile.chapterTitleFormat = "none"

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: noHeadingCompile,
            read: { contents[$0]! }
        )

        #expect(assembled == "Text.")
    }

    @Test("assembleMatter joins flat sections with no generated headings")
    func assemblesMatterWithoutHeadings() throws {
        let titlePage = url("FrontMatter/02 Title Page.md")
        let copyright = url("FrontMatter/03 Copyright.md")
        let contents: [URL: String] = [
            titlePage: "# The Last Shift\n\nTim Fleet",
            copyright: "# Copyright\n\nCopyright \u{00A9} 2026."
        ]

        let assembled = try ManuscriptAssembler.assembleMatter(
            [SceneNode(url: titlePage, displayName: "Title Page"), SceneNode(url: copyright, displayName: "Copyright")],
            read: { contents[$0]! }
        )

        #expect(assembled == "# The Last Shift\n\nTim Fleet\n\n# Copyright\n\nCopyright \u{00A9} 2026.")
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
