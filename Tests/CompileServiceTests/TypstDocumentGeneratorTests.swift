import ProjectStore
import Testing
@testable import CompileService

@Suite("TypstDocumentGenerator")
struct TypstDocumentGeneratorTests {
    /// A representative slice of pandoc's real default typst template (captured via
    /// `pandoc --print-default-template=typst`), just enough to exercise the marker
    /// replacement without embedding the whole ~150-line file in every test.
    private let samplePandocTemplate = """
        #let horizontalRule = line(start: (25%,0%), end: (75%,0%))
        #let divider = if "divider" in std { divider } else { horizontalRule }

        $if(template)$
        #import "$template$": conf
        $else$
        $template.typst()$
        $endif$

        #show: doc => conf(
        $if(title)$
          title: [$title$],
        $endif$
          doc,
        )

        $body$
        """

    @Test("replaces pandoc's import marker with an inlined conf function")
    func replacesImportMarker() {
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.375,
            print: ProjectMetadata.Print()
        )

        #expect(result.contains("#import \"$template$\": conf") == false)
        #expect(result.contains("#let conf("))
        // The surrounding template (the #show: doc => conf(...) call and $body$) must
        // survive untouched — this is exactly what a plain --template replacement loses.
        #expect(result.contains("#show: doc => conf("))
        #expect(result.contains("$body$"))
    }

    @Test("embeds trim size dimensions")
    func embedsTrimSizeDimensions() {
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .sixByNine,
            gutterInches: 0.375,
            print: ProjectMetadata.Print()
        )
        #expect(result.contains("width: 6.0in"))
        #expect(result.contains("height: 9.0in"))
    }

    @Test("inside margin adds the gutter to the fixed outside margin")
    func insideMarginAddsGutter() {
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.5,
            print: ProjectMetadata.Print()
        )
        #expect(result.contains("inside: 1.0in"))
        #expect(result.contains("outside: 0.5in"))
        #expect(result.contains("top: 0.75in"))
        #expect(result.contains("bottom: 0.8in"))
    }

    @Test("embeds the body font, point size, and leading from print settings")
    func embedsBodyTypography() {
        var print = ProjectMetadata.Print()
        print.bodyFont = "EB Garamond"
        print.bodyPointSize = 11.5
        print.leading = 1.4
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.375,
            print: print
        )

        #expect(result.contains("\"EB Garamond\""))
        #expect(result.contains("size: 11.5pt"))
        // `print.leading` is the *total* desired line pitch (§ TypstDocumentGenerator's
        // own comment) — Typst's `par.leading` means extra space on top of the font's
        // natural line height, so the template converts rather than passing it straight
        // through; assert the conversion is present rather than a literal "1.4em".
        // 0.6465 is EB Garamond's own measured natural line height (§
        // `naturalLineHeightEm(forFont:)`), not the old flat 0.68em average.
        #expect(result.contains("calc.max(0.05, 1.4 - 0.6465)"))
        #expect(result.contains("leading: typstLeadingEm * 1em"))
    }

    @Test("front/back matter get an unnumbered, header-free page break; body restarts numbering at 1")
    func frontBackMatterNumberingAndHeader() {
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.375,
            print: ProjectMetadata.Print()
        )

        // Every FrontBackMatterTemplate anchor ID is embedded as a Typst label so the
        // heading show-rule can recognize front/back matter regardless of the
        // `.hidden-heading`/`.title-page-heading` CSS class pandoc's typst writer
        // drops on the way from markdown.
        for template in FrontBackMatterTemplate.allCases {
            #expect(result.contains("<\(template.anchorID)>"))
        }
        // Front matter's own numbering is suppressed entirely, and the body's real
        // page count restarts at 1 once it begins — both need `bodyStartPage`'s state,
        // not `numbering:`'s built-in string-pattern form.
        #expect(result.contains("numbering: none"))
        #expect(result.contains("bodyStartPage"))
        // The very first heading in the document never gets a leading pagebreak —
        // it's already at the top of a blank page 1 — tracked via an explicit
        // "have we placed any heading yet" state rather than page position, since a
        // short front-matter page might not advance the physical page counter at all.
        #expect(result.contains("seenHeading"))
        // Copyright/Dedication/A Note From/Newsletter never show their own heading
        // text on the page (§ FrontBackMatterTemplate.showsHeadingOnPage).
        for template in FrontBackMatterTemplate.allCases where !template.showsHeadingOnPage {
            #expect(result.contains("<\(template.anchorID)>"))
        }
        #expect(result.contains("hiddenHeadingLabels"))
        // A chapter's own opening page never shows the running head — found by
        // querying heading locations directly rather than a state read, since a state
        // set by a heading further down *this same page* isn't visible yet to that
        // page's own header (verified against a real compile: a state-based version
        // only ever suppressed the header on the very first chapter, not every one).
        #expect(result.contains("query(heading.where(level: 1))"))
        // Back matter drops the page number the same way front matter does, once its
        // own first heading begins — the footer only re-derived from `bodyStartPage`
        // would have kept numbering straight through the back-matter notes, matching
        // an earlier real compile where "About the Author" wrongly still showed a
        // page number.
        #expect(result.contains("backMatterStarted"))
        // Copyright/Dedication/A Note From/Newsletter sit vertically centered on their
        // own page (matching the `.centered-page` div class pandoc's typst writer
        // drops on the way from markdown) via a `v(1fr)` pair sandwiching the section
        // — a single leading `v(1fr)` alone would push the content to the bottom of
        // the page instead of centering it, so the closing one has to fire right
        // before the *next* heading's own pagebreak.
        #expect(result.contains("centerCurrentSection"))
        #expect(result.contains("v(1fr)"))
    }

    @Test("chapter openers use pagebreak(to: \"odd\") when configured for recto")
    func rectoChapterOpenersUseOddPagebreak() {
        var print = ProjectMetadata.Print()
        print.chapterOpensOn = "recto"
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.375,
            print: print
        )

        #expect(result.contains("pagebreak(to: \"odd\")"))
    }

    @Test("a non-recto chapterOpensOn setting uses a plain pagebreak")
    func nonRectoUsesPlainPagebreak() {
        var print = ProjectMetadata.Print()
        print.chapterOpensOn = "either"
        let result = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: samplePandocTemplate,
            trimSize: .fiveByEight,
            gutterInches: 0.375,
            print: print
        )

        #expect(result.contains("pagebreak(to: \"odd\")") == false)
        #expect(result.contains("pagebreak()"))
    }

    @Test("applyCenteredMatterStyling centers Title Page/Copyright/Dedication/A Note From/Newsletter, and only those")
    func appliesCenteredMatterStylingToHiddenHeadingMatterOnly() {
        // Mirrors what pandoc's typst writer actually emits for a `::: {.centered-page}`
        // div right after one of these labels — a bare `#block[...]`, with the div's
        // own CSS class already dropped (same loss the heading classes suffer).
        func fixture(label: String) -> String {
            "<\(label)>\n#block[\nSome body copy.\n]\n"
        }
        let source = FrontBackMatterTemplate.allCases.map { fixture(label: $0.anchorID) }.joined(separator: "\n")
        let result = TypstDocumentGenerator.applyCenteredMatterStyling(to: source, bodyPointSize: 11.5)

        // Title Page's own byline is wrapped in the same `.centered-page` div as the
        // hidden-heading matter, so it gets the same centering even though its heading
        // itself goes through a different branch (§ the function's own doc comment).
        for template in FrontBackMatterTemplate.allCases where !template.showsHeadingOnPage || template == .titlePage {
            #expect(result.contains("<\(template.anchorID)>\n#block(width: 100%)[\n#set align(center)"))
        }
        // About the Author shows its own heading over ordinary block prose, not a
        // `.centered-page` div — this pass must leave its block untouched.
        #expect(result.contains("<about-the-author>\n#block[\nSome body copy."))
    }

    @Test("applyFlushFirstParagraphAfterChapterHeadings flushes only the paragraph right after a chapter heading")
    func flushesFirstParagraphAfterChapterHeadingsOnly() {
        let source = """
            = Chapter One
            <chapter-1>
            First paragraph, wrapped across
            two source lines by pandoc.

            Second paragraph stays at the normal indent.

            = Copyright
            <copyright>
            #block[
            Copyright body copy — never touched by this pass.
            ]

            = About the Author
            <about-the-author>
            Drew Calloway writes crime thrillers.
            """
        let result = TypstDocumentGenerator.applyFlushFirstParagraphAfterChapterHeadings(to: source, firstLineIndentEm: 1.0)

        #expect(result.contains("<chapter-1>\n#set par(first-line-indent: 0em)\nFirst paragraph, wrapped across\ntwo source lines by pandoc."))
        #expect(result.contains("#set par(first-line-indent: 1.0em)\n\nSecond paragraph stays at the normal indent."))
        // Copyright's body copy is handled by `applyCenteredMatterStyling` instead —
        // this pass must not also touch it.
        #expect(result.contains("<copyright>\n#block[\nCopyright body copy"))
        // About the Author's body is ordinary block prose, not a `.centered-page` div
        // — unlike Copyright, it has no other pass to flush its opening paragraph, so
        // this one must reach it. Deliberately no trailing blank line after it (Swift's
        // multi-line string literal drops the final `\n`) — About the Author really is
        // the very last thing pandoc emits for a full compile, EOF and all, and this
        // must still flush it rather than requiring a `\n\n` that will never come.
        #expect(result.contains("<about-the-author>\n#set par(first-line-indent: 0em)\nDrew Calloway writes crime thrillers."))
    }

    @Test("applySceneBreakOrnament replaces pandoc's default divider call")
    func replacesDividerCall() {
        let source = "Some text.\n\n#divider()\n\nMore text."
        let result = TypstDocumentGenerator.applySceneBreakOrnament(to: source)

        #expect(result.contains("#divider()") == false)
        #expect(result.contains("\\* \\* \\*"))
        #expect(result.contains("Some text."))
        #expect(result.contains("More text."))
    }

    @Test("applySceneBreakOrnament escapes the asterisks — unescaped '* * *' is invalid typst markup (unclosed strong-emphasis delimiter)")
    func escapesAsterisksForTypstMarkup() {
        let result = TypstDocumentGenerator.applySceneBreakOrnament(to: "#divider()")

        // A bare, unescaped "* * *" inside a typst content block (`[...]`) doesn't
        // render as three asterisks — `*` opens/closes strong emphasis, so this
        // parses as an emphasis span followed by a dangling unclosed `*`, which a
        // real typst compile rejects outright. Confirmed against typst 0.15.1.
        #expect(result.contains("* * *") == false)
        #expect(result.contains("\\* \\* \\*"))
    }
}
