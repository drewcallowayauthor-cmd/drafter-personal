import Testing
@testable import CompileService

@Suite("SMFSceneSeparatorFormatter")
struct SMFSceneSeparatorFormatterTests {
    @Test("replaces a bare # separator line with a centered raw openxml paragraph")
    func replacesBareHashSeparator() {
        let manuscript = "First scene.\n\n#\n\nSecond scene."
        let output = SMFSceneSeparatorFormatter.format(manuscript, separator: "#")
        #expect(output.contains("```{=openxml}"))
        #expect(output.contains("<w:pStyle w:val=\"SMFSceneBreak\" />"))
        #expect(output.contains("<w:t xml:space=\"preserve\">#</w:t>"))
        // Not left as a bare markdown line — that's what pandoc parses as an empty
        // ATX heading (renders as invisible blank space) in the first place.
        #expect(!output.contains("\n\n#\n\n"))
    }

    @Test("replaces a * * * separator line rather than leaving it as a thematic break")
    func replacesAsteriskSeparator() {
        let manuscript = "First scene.\n\n* * *\n\nSecond scene."
        let output = SMFSceneSeparatorFormatter.format(manuscript, separator: "* * *")
        #expect(output.contains("<w:t xml:space=\"preserve\">* * *</w:t>"))
        #expect(!output.contains("\n\n* * *\n\n"))
    }

    @Test("does not touch the separator text when it appears inside prose, only standalone lines")
    func onlyStandaloneLines() {
        let manuscript = "She wrote # on the board.\n\n#\n\nMore text."
        let output = SMFSceneSeparatorFormatter.format(manuscript, separator: "#")
        #expect(output.contains("She wrote # on the board."))
        #expect(output.contains("<w:pStyle w:val=\"SMFSceneBreak\" />"))
    }

    @Test("no-ops when the separator is empty")
    func emptySeparatorNoOp() {
        let manuscript = "First scene.\n\n\n\nSecond scene."
        #expect(SMFSceneSeparatorFormatter.format(manuscript, separator: "") == manuscript)
    }

    @Test("leaves text with no matching separator lines untouched")
    func noMatchNoOp() {
        let manuscript = "Just prose, no separators here."
        #expect(SMFSceneSeparatorFormatter.format(manuscript, separator: "#") == manuscript)
    }
}
