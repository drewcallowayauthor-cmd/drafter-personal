import Testing
@testable import CompileService

@Suite("SMFChapterOpenerSpacer")
struct SMFChapterOpenerSpacerTests {
    @Test("inserts a raw openxml spacer block immediately before a chapter heading")
    func insertsSpacerBeforeHeading() {
        let manuscript = "# Chapter One {.chapter-title #chapter-1}\n\nThe phone was ringing."
        let output = SMFChapterOpenerSpacer.insertSpacing(into: manuscript)
        #expect(output.contains("```{=openxml}"))
        let spacerIndex = output.range(of: "```{=openxml}")!.lowerBound
        let headingIndex = output.range(of: "# Chapter One")!.lowerBound
        #expect(spacerIndex < headingIndex)
        #expect(output.contains("The phone was ringing."))
    }

    @Test("only the first spacer paragraph carries the page break")
    func onlyFirstParagraphBreaksPage() {
        let manuscript = "# Chapter One {.chapter-title #chapter-1}\n\nBody."
        let output = SMFChapterOpenerSpacer.insertSpacing(into: manuscript, blankLines: 3)
        #expect(output.components(separatedBy: "<w:pageBreakBefore").count - 1 == 1)
        #expect(output.components(separatedBy: "ChapterSpacer").count - 1 == 3)
    }

    @Test("inserts a spacer block before every chapter heading, not just the first")
    func insertsBeforeEveryHeading() {
        let manuscript = """
        # Chapter One {.chapter-title #chapter-1}

        First chapter body.

        # Chapter Two {.chapter-title #chapter-2}

        Second chapter body.
        """
        let output = SMFChapterOpenerSpacer.insertSpacing(into: manuscript, blankLines: 2)
        #expect(output.components(separatedBy: "```{=openxml}").count - 1 == 2)
    }

    @Test("leaves manuscript text with no chapter headings untouched")
    func noHeadingsNoOp() {
        let manuscript = "Just some prose with no heading."
        #expect(SMFChapterOpenerSpacer.insertSpacing(into: manuscript) == manuscript)
    }
}
