import Testing
@testable import ProjectStore

@Suite("FilenamePrefix")
struct FilenamePrefixTests {
    @Test("parses a well-formed prefix and display name")
    func parsesWellFormed() {
        let parsed = FilenamePrefix.parse("02 The Board.md")
        #expect(parsed.prefix == 2)
        #expect(parsed.displayName == "The Board")
    }

    @Test("treats a missing prefix as nil rather than throwing")
    func toleratesMissingPrefix() {
        let parsed = FilenamePrefix.parse("Interlude.md")
        #expect(parsed.prefix == nil)
        #expect(parsed.displayName == "Interlude")
    }

    @Test("sorts by prefix, tolerating duplicates and gaps")
    func sortsByPrefix() {
        let sorted = FilenamePrefix.sort([
            "03 Room Nine.md",
            "01 Triage.md",
            "02 The Board.md"
        ])
        #expect(sorted == ["01 Triage.md", "02 The Board.md", "03 Room Nine.md"])
    }

    @Test("files without a prefix sort after prefixed siblings, alphabetically among themselves")
    func unprefixedSortAfterAndAlphabetically() {
        let sorted = FilenamePrefix.sort([
            "Zebra.md",
            "01 Triage.md",
            "Apple.md"
        ])
        #expect(sorted == ["01 Triage.md", "Apple.md", "Zebra.md"])
    }

    @Test("resequence produces dense zero-padded prefixes in the given order")
    func resequenceProducesDensePrefixes() {
        let resequenced = FilenamePrefix.resequence(displayNames: ["Triage", "The Board", "Room Nine"])
        #expect(resequenced == ["01 Triage", "02 The Board", "03 Room Nine"])
    }

    @Test("resequence uses 3 digits past 99 items")
    func resequenceUsesThreeDigitsPastNinetyNine() {
        let names = (1...101).map { "Scene \($0)" }
        let resequenced = FilenamePrefix.resequence(displayNames: names, digits: 3)
        #expect(resequenced.first == "001 Scene 1")
        #expect(resequenced.last == "101 Scene 101")
    }

    @Test("nextFilename picks one past the highest existing prefix")
    func nextFilenamePicksOnePastHighest() {
        let filename = FilenamePrefix.nextFilename(
            existingFilenames: ["01 Triage.md", "03 Room Nine.md"],
            title: "Code Blue",
            extension: "md"
        )
        #expect(filename == "04 Code Blue.md")
    }

    @Test("nextFilename starts at 01 with nothing existing")
    func nextFilenameStartsAtOne() {
        let filename = FilenamePrefix.nextFilename(existingFilenames: [], title: "Arrival", extension: nil)
        #expect(filename == "01 Arrival")
    }

    @Test("nextFilename with no extension omits the trailing dot, for a chapter folder")
    func nextFilenameWithNoExtensionOmitsDot() {
        let filename = FilenamePrefix.nextFilename(existingFilenames: ["01 Arrival"], title: "The First Hour", extension: nil)
        #expect(filename == "02 The First Hour")
    }

    @Test("nextFilename switches to 3 digits past 99 existing items")
    func nextFilenameSwitchesToThreeDigits() {
        let existing = (1...99).map { "\(String(format: "%02d", $0)) Scene.md" }
        let filename = FilenamePrefix.nextFilename(existingFilenames: existing, title: "Overflow", extension: "md")
        #expect(filename == "100 Overflow.md")
    }

    @Test("sanitize replaces illegal filename characters with a hyphen")
    func sanitizeReplacesIllegalCharacters() {
        #expect(FilenamePrefix.sanitize("Before: After / Then?") == "Before- After - Then-")
    }

    @Test("sanitize falls back to Untitled when nothing legal remains")
    func sanitizeFallsBackToUntitled() {
        #expect(FilenamePrefix.sanitize("   ") == "Untitled")
    }
}
