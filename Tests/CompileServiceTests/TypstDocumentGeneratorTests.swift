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
        #expect(result.contains("top: 0.8in"))
        #expect(result.contains("bottom: 1.0in"))
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
        #expect(result.contains("leading: 1.4em"))
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

    @Test("applySceneBreakOrnament replaces pandoc's default divider call")
    func replacesDividerCall() {
        let source = "Some text.\n\n#divider()\n\nMore text."
        let result = TypstDocumentGenerator.applySceneBreakOrnament(to: source)

        #expect(result.contains("#divider()") == false)
        #expect(result.contains("* * *"))
        #expect(result.contains("Some text."))
        #expect(result.contains("More text."))
    }
}
