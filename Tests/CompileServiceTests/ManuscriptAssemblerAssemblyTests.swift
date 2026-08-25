import Foundation
import ProjectStore
import Testing
@testable import CompileService

/// `assembleMatter`/`assembleFull`/short-story assembly coverage for `ManuscriptAssembler`,
/// split out of `ManuscriptAssemblerTests` to keep both files under SwiftLint's
/// file/type-body length limits.
@Suite("ManuscriptAssembler assembly")
struct ManuscriptAssemblerAssemblyTests {
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

        let assembled = try ManuscriptAssembler.assembleFull(
            binderTree: tree, compile: compile, read: { contents[$0]! }
        )

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

        let assembled = try ManuscriptAssembler.assembleFull(
            binderTree: tree, compile: compile, read: { contents[$0]! }
        )

        #expect(assembled.contains("# Title Page") == false)
        #expect(assembled.contains("Manuscript text."))
    }

    @Test("short story assembly wraps the whole manuscript in one hidden heading with bare numbered h2 scenes")
    func shortStoryWrapsManuscriptInOneHiddenHeading() throws {
        let scene1 = url("Manuscript/01 Arrival/01 Triage.md")
        let scene2 = url("Manuscript/02 Departure/01 Goodbye.md")
        let chapters = [
            ChapterNode(
                url: url("Manuscript/01 Arrival"),
                displayName: "Arrival",
                scenes: [SceneNode(url: scene1, displayName: "Triage")],
                isLooseFile: false
            ),
            ChapterNode(
                url: url("Manuscript/02 Departure"),
                displayName: "Departure",
                scenes: [SceneNode(url: scene2, displayName: "Goodbye")],
                isLooseFile: false
            )
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
        let chapter = ChapterNode(
            url: url("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
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
