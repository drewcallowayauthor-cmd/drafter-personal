import Testing
@testable import CompileService

@Suite("WordCounter")
struct WordCounterTests {
    @Test("counts plain prose")
    func plainProse() {
        #expect(WordCounter.count("The board was wrong.") == 4)
    }

    @Test("strips YAML front matter before counting")
    func stripsFrontMatter() {
        let scene = """
        ---
        synopsis: Sam takes over the board.
        status: draft
        ---

        The board was wrong.
        """
        #expect(WordCounter.count(scene) == 4)
    }

    @Test("strips emphasis markers without dropping the words")
    func stripsEmphasisMarkers() {
        #expect(WordCounter.count("It was *never* going to be **easy**.") == 7)
    }

    @Test("excludes scene separator lines")
    func excludesSceneSeparator() {
        let text = "First scene.\n\n* * *\n\nSecond scene."
        #expect(WordCounter.count(text) == 4)
    }

    @Test("counts hyphenated compounds as one word")
    func hyphenatedCompoundsCountAsOne() {
        #expect(WordCounter.count("A well-lit, ten-year-old hallway.") == 4)
    }

    @Test("excludes standalone punctuation tokens")
    func excludesStandalonePunctuation() {
        #expect(WordCounter.count("Wait — no.") == 2)
    }

    @Test("strips HTML comments")
    func stripsHTMLComments() {
        #expect(WordCounter.count("Visible text. <!-- editor note, ignore -->") == 2)
    }

    @Test("empty scene counts zero")
    func emptyScene() {
        #expect(WordCounter.count("") == 0)
    }
}
