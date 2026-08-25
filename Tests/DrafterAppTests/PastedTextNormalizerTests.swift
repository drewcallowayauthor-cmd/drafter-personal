import Testing
@testable import DrafterApp

@Suite("PastedTextNormalizer")
struct PastedTextNormalizerTests {
    @Test("plain \\n text is left untouched")
    func leavesPlainTextUntouched() {
        let text = "First paragraph.\n\nSecond paragraph."
        #expect(PastedTextNormalizer.normalize(text) == text)
    }

    @Test("CRLF (Windows) line endings become \\n")
    func normalizesCRLF() {
        #expect(
            PastedTextNormalizer.normalize("First paragraph.\r\n\r\nSecond paragraph.")
                == "First paragraph.\n\nSecond paragraph."
        )
    }

    @Test("bare CR (classic Mac) line endings become \\n")
    func normalizesBareCR() {
        #expect(
            PastedTextNormalizer.normalize("First paragraph.\r\rSecond paragraph.")
                == "First paragraph.\n\nSecond paragraph."
        )
    }

    @Test("Unicode line separator (U+2028) and paragraph separator (U+2029) become a paragraph break")
    func normalizesUnicodeSeparators() {
        // Each becomes a lone `\n` after unification, then gets promoted the same way
        // any other lone newline does (§ promoteLoneNewlinesToParagraphBreaks).
        #expect(PastedTextNormalizer.normalize("First\u{2028}Second\u{2029}Third") == "First\n\nSecond\n\nThird")
    }

    @Test("a mix of line-ending styles in one paste all normalize and promote consistently")
    func normalizesMixedLineEndings() {
        let mixed = "One.\r\nTwo.\rThree.\u{2028}Four.\u{2029}Five.\nSix."
        #expect(PastedTextNormalizer.normalize(mixed) == "One.\n\nTwo.\n\nThree.\n\nFour.\n\nFive.\n\nSix.")
    }

    @Test("a lone newline between paragraphs (Scrivener RTF's convention) is promoted to a blank-line break")
    func promotesLoneNewlineToParagraphBreak() {
        let scrivenerStyle =
            "The phone was already ringing when I put the coffee on. I let it go.\nIt stopped before I had my boots on."
        #expect(
            PastedTextNormalizer.normalize(scrivenerStyle) ==
                // swiftlint:disable:next line_length
                "The phone was already ringing when I put the coffee on. I let it go.\n\nIt stopped before I had my boots on."
        )
    }

    @Test("an existing blank-line paragraph break is left exactly as-is, not expanded further")
    func leavesExistingBlankLineUntouched() {
        let text = "First paragraph.\n\nSecond paragraph."
        #expect(PastedTextNormalizer.normalize(text) == text)
    }

    @Test("three or more consecutive newlines are left untouched rather than compounded")
    func leavesExtraBlankLinesUntouched() {
        let text = "First paragraph.\n\n\nSecond paragraph."
        #expect(PastedTextNormalizer.normalize(text) == text)
    }

    @Test("multiple lone-newline paragraphs in a row (a whole pasted chapter) all get promoted")
    func promotesManyConsecutiveLoneNewlines() {
        let manuscript = "Para one.\nPara two.\nPara three."
        #expect(PastedTextNormalizer.normalize(manuscript) == "Para one.\n\nPara two.\n\nPara three.")
    }
}
