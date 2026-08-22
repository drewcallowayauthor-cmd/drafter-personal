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

        #expect(assembled == "# Chapter 1 {.chapter-title #chapter-1}\n\nFirst scene text.\n\n#\n\nSecond scene text.")
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

        #expect(assembled == "# Chapter 1 {.chapter-title #chapter-1}\n\nInterlude text.")
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

        #expect(assembled == "# Chapter 1 {.chapter-title #chapter-1}\n\nKept.")
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

        #expect(assembled == "# Chapter 1 {.chapter-title #chapter-1}\n\nKept.")
    }

    @Test("a Prologue doesn't consume a chapter number — the chapter after it is still Chapter 1")
    func prologueDoesNotConsumeAChapterNumber() throws {
        let prologueScene = url("Manuscript/01 Prologue/01 Only Scene.md")
        let arrivalScene = url("Manuscript/02 Arrival/01 Triage.md")
        let prologue = ChapterNode(
            url: url("Manuscript/01 Prologue"),
            displayName: "Prologue",
            scenes: [SceneNode(url: prologueScene, displayName: "Only Scene")],
            isLooseFile: false
        )
        let arrival = ChapterNode(
            url: url("Manuscript/02 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: arrivalScene, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [prologue, arrival], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            prologueScene: scene("Before it all began."),
            arrivalScene: scene("It began.")
        ]

        let assembled = try ManuscriptAssembler.assembleManuscript(
            binderTree: tree,
            compile: compile,
            read: { contents[$0]! }
        )

        #expect(assembled == "# Prologue {.chapter-title #prologue}\n\nBefore it all began.\n\n# Chapter 1 {.chapter-title #chapter-1}\n\nIt began.")
    }

    @Test("chapterEntries mirrors assembleManuscript's headings/anchors, including a Prologue's own anchor")
    func chapterEntriesMirrorAssembledHeadings() throws {
        let prologueScene = url("Manuscript/01 Prologue/01 Only Scene.md")
        let arrivalScene = url("Manuscript/02 Arrival/01 Triage.md")
        let prologue = ChapterNode(
            url: url("Manuscript/01 Prologue"),
            displayName: "Prologue",
            scenes: [SceneNode(url: prologueScene, displayName: "Only Scene")],
            isLooseFile: false
        )
        let arrival = ChapterNode(
            url: url("Manuscript/02 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: arrivalScene, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [prologue, arrival], frontMatter: [], backMatter: [], notes: [])
        let contents: [URL: String] = [
            prologueScene: scene("Before it all began."),
            arrivalScene: scene("It began.")
        ]

        let entries = try ManuscriptAssembler.chapterEntries(binderTree: tree, compile: compile, read: { contents[$0]! })

        #expect(entries == [
            .init(title: "Prologue", anchorID: "prologue"),
            .init(title: "Chapter 1", anchorID: "chapter-1")
        ])
    }

    @Test("chapterEntries is empty when chapterTitleFormat is 'none', matching the headingless output")
    func chapterEntriesEmptyWhenFormatIsNone() throws {
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

        let entries = try ManuscriptAssembler.chapterEntries(
            binderTree: tree,
            compile: noHeadingCompile,
            read: { contents[$0]! }
        )

        #expect(entries.isEmpty)
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
            titlePage: "# Last Call\n\nDrew Calloway",
            copyright: "# Copyright\n\nCopyright \u{00A9} 2026."
        ]

        let assembled = try ManuscriptAssembler.assembleMatter(
            [SceneNode(url: titlePage, displayName: "Title Page"), SceneNode(url: copyright, displayName: "Copyright")],
            read: { contents[$0]! }
        )

        #expect(assembled == "# Last Call\n\nDrew Calloway\n\n# Copyright\n\nCopyright \u{00A9} 2026.")
    }

    @Test("assembleFull joins front matter, manuscript, and back matter when both toggles are on")
    func assembleFullJoinsAllThreeSections() throws {
        let sceneURL = url("Manuscript/01 Arrival/01 Triage.md")
        let frontURL = url("FrontMatter/02 Title Page.md")
        let backURL = url("BackMatter/01 About the Author.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(
            manuscript: [chapter],
            frontMatter: [SceneNode(url: frontURL, displayName: "Title Page")],
            backMatter: [SceneNode(url: backURL, displayName: "About the Author")],
            notes: []
        )
        var compile = ProjectMetadata.Compile()
        compile.includeFrontMatter = true
        compile.includeBackMatter = true
        let contents: [URL: String] = [
            sceneURL: scene("Manuscript text."),
            frontURL: "# Title Page",
            backURL: "# About the Author"
        ]

        let assembled = try ManuscriptAssembler.assembleFull(binderTree: tree, compile: compile, read: { contents[$0]! })

        #expect(assembled.contains("# Title Page"))
        #expect(assembled.contains("Manuscript text."))
        #expect(assembled.contains("# About the Author"))
        // Front matter must come first, back matter last.
        let frontRange = assembled.range(of: "# Title Page")!
        let bodyRange = assembled.range(of: "Manuscript text.")!
        let backRange = assembled.range(of: "# About the Author")!
        #expect(frontRange.lowerBound < bodyRange.lowerBound)
        #expect(bodyRange.lowerBound < backRange.lowerBound)
    }

    @Test("assembleFull omits front and back matter when their toggles are off")
    func assembleFullOmitsDisabledSections() throws {
        let sceneURL = url("Manuscript/01 Arrival/01 Triage.md")
        let frontURL = url("FrontMatter/02 Title Page.md")
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(
            manuscript: [chapter],
            frontMatter: [SceneNode(url: frontURL, displayName: "Title Page")],
            backMatter: [],
            notes: []
        )
        var compile = ProjectMetadata.Compile()
        compile.includeFrontMatter = false
        let contents: [URL: String] = [sceneURL: scene("Manuscript text."), frontURL: "# Title Page"]

        let assembled = try ManuscriptAssembler.assembleFull(binderTree: tree, compile: compile, read: { contents[$0]! })

        #expect(assembled.contains("# Title Page") == false)
        #expect(assembled.contains("Manuscript text."))
    }

    @Test("short story assembly wraps the whole manuscript in one hidden heading with bare numbered h2 scenes")
    func shortStoryWrapsManuscriptInOneHiddenHeading() throws {
        let scene1 = url("Manuscript/01 Arrival/01 Triage.md")
        let scene2 = url("Manuscript/02 Departure/01 Goodbye.md")
        let chapters = [
            ChapterNode(url: url("Manuscript/01 Arrival"), displayName: "Arrival", scenes: [SceneNode(url: scene1, displayName: "Triage")], isLooseFile: false),
            ChapterNode(url: url("Manuscript/02 Departure"), displayName: "Departure", scenes: [SceneNode(url: scene2, displayName: "Goodbye")], isLooseFile: false)
        ]
        let tree = BinderTree(manuscript: chapters, frontMatter: [], backMatter: [], notes: [])
        var compile = ProjectMetadata.Compile()
        compile.chapterTitleFormat = "{n}"
        let contents: [URL: String] = [
            scene1: scene("First scene text."),
            scene2: scene("Second scene text.")
        ]

        let assembled = try ManuscriptAssembler.assembleShortStoryManuscript(
            binderTree: tree,
            compile: compile,
            title: "Rook Takes",
            read: { contents[$0]! }
        )

        #expect(assembled == """
            # Rook Takes {.hidden-heading #manuscript}

            ## 1 {#chapter-1}

            First scene text.

            ## 2 {#chapter-2}

            Second scene text.
            """)
    }

    @Test("short story Contents entry is a single title link, not one per chapter")
    func shortStoryContentsEntryIsSingleTitleLink() throws {
        let sceneURL = url("Manuscript/01 Arrival/01 Triage.md")
        let chapter = ChapterNode(url: url("Manuscript/01 Arrival"), displayName: "Arrival", scenes: [SceneNode(url: sceneURL, displayName: "Triage")], isLooseFile: false)
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        var compile = ProjectMetadata.Compile()
        compile.chapterTitleFormat = "{n}"
        let contents: [URL: String] = [sceneURL: scene("Scene text.")]

        let entry = try ManuscriptAssembler.shortStoryContentsEntry(
            binderTree: tree,
            compile: compile,
            title: "Rook Takes",
            read: { contents[$0]! }
        )

        #expect(entry == ManuscriptAssembler.ChapterEntry(title: "Rook Takes", anchorID: "manuscript"))
    }

    @Test("short story Contents entry is nil for an empty manuscript")
    func shortStoryContentsEntryNilWhenEmpty() throws {
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let compile = ProjectMetadata.Compile()

        let entry = try ManuscriptAssembler.shortStoryContentsEntry(
            binderTree: tree,
            compile: compile,
            title: "Rook Takes",
            read: { _ in "" }
        )

        #expect(entry == nil)
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
