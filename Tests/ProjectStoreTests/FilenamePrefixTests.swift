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
}
