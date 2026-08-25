import Testing
@testable import CompileService

@Suite("ChapterHeadingFormatter")
struct ChapterHeadingFormatterTests {
    @Test("substitutes {n}")
    func substitutesN() {
        #expect(ChapterHeadingFormatter.heading(format: "Chapter {n}", index: 3, title: "Arrival") == "Chapter 3")
    }

    @Test("substitutes {n_word}")
    func substitutesNWord() {
        #expect(
            ChapterHeadingFormatter.heading(format: "Chapter {n_word}", index: 3, title: "Arrival") == "Chapter Three"
        )
    }

    @Test("substitutes {title}")
    func substitutesTitle() {
        #expect(ChapterHeadingFormatter.heading(format: "{title}", index: 1, title: "Arrival") == "Arrival")
    }

    @Test("none emits no heading")
    func noneEmitsNoHeading() {
        #expect(ChapterHeadingFormatter.heading(format: "none", index: 1, title: "Arrival") == nil)
    }

    @Test("spells twenty-one, one hundred, and compound hundreds correctly")
    func spellsCompoundNumbers() {
        #expect(ChapterHeadingFormatter.heading(format: "{n_word}", index: 21, title: "") == "Twenty-One")
        #expect(ChapterHeadingFormatter.heading(format: "{n_word}", index: 100, title: "") == "One Hundred")
        #expect(ChapterHeadingFormatter.heading(format: "{n_word}", index: 101, title: "") == "One Hundred One")
    }

    @Test("can combine multiple tokens in one format")
    func combinesTokens() {
        let heading = ChapterHeadingFormatter.heading(format: "{n}. {title}", index: 2, title: "The First Hour")
        #expect(heading == "2. The First Hour")
    }

    @Test("Prologue and Epilogue emit their title as-is, ignoring the numbered format")
    func prologueAndEpilogueIgnoreFormat() {
        #expect(ChapterHeadingFormatter.heading(format: "Chapter {n}", index: 1, title: "Prologue") == "Prologue")
        #expect(ChapterHeadingFormatter.heading(format: "Chapter {n}", index: 7, title: "Epilogue") == "Epilogue")
    }

    @Test("Prologue/Epilogue detection is case-insensitive and ignores surrounding whitespace")
    func prologueDetectionIsCaseInsensitive() {
        #expect(ChapterHeadingFormatter.isUnnumbered(title: "prologue"))
        #expect(ChapterHeadingFormatter.isUnnumbered(title: "EPILOGUE"))
        #expect(ChapterHeadingFormatter.isUnnumbered(title: "  Prologue  "))
        #expect(ChapterHeadingFormatter.isUnnumbered(title: "Prologue: The Board") == false)
    }

    @Test("'none' still suppresses a Prologue/Epilogue heading")
    func noneFormatSuppressesPrologueToo() {
        #expect(ChapterHeadingFormatter.heading(format: "none", index: 1, title: "Prologue") == nil)
    }
}
