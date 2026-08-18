import Testing
@testable import DrafterApp

@Suite("SceneDiff")
struct SceneDiffTests {
    @Test("identical text produces only unchanged lines")
    func identicalTextIsAllUnchanged() {
        let text = "First paragraph.\n\nSecond paragraph."
        let diff = SceneDiff.diff(old: text, new: text)

        #expect(diff.allSatisfy { $0.kind == .unchanged })
        #expect(diff.count == 3)
    }

    @Test("a purely added paragraph is marked .added with no word sub-diff")
    func pureAdditionIsMarkedAdded() {
        let old = "First paragraph."
        let new = "First paragraph.\n\nSecond paragraph."
        let diff = SceneDiff.diff(old: old, new: new)

        #expect(diff[0].kind == .unchanged)
        #expect(diff.contains { $0.kind == .added && $0.newText == "Second paragraph." })
    }

    @Test("a purely removed paragraph is marked .removed")
    func pureRemovalIsMarkedRemoved() {
        let old = "First paragraph.\n\nSecond paragraph."
        let new = "First paragraph."
        let diff = SceneDiff.diff(old: old, new: new)

        #expect(diff.contains { $0.kind == .removed && $0.oldText == "Second paragraph." })
    }

    @Test("an edited paragraph is marked .modified with word-level operations on both sides")
    func editedParagraphIsModifiedWithWordDiff() {
        let old = "The board was wrong."
        let new = "The board was terribly wrong."
        let diff = SceneDiff.diff(old: old, new: new)

        #expect(diff.count == 1)
        #expect(diff[0].kind == .modified)
        #expect(diff[0].newWords?.contains(.insert("terribly")) == true)
        #expect(diff[0].oldWords?.contains(.insert("terribly")) != true)
    }

    @Test("word-level diff on the modified paragraph preserves unchanged words")
    func modifiedParagraphKeepsUnchangedWordsOnBothSides() {
        let old = "Sam checked the board twice."
        let new = "Sam checked the board three times."
        let diff = SceneDiff.diff(old: old, new: new)

        #expect(diff[0].oldWords?.contains(.equal("Sam")) == true)
        #expect(diff[0].newWords?.contains(.equal("Sam")) == true)
        #expect(diff[0].oldWords?.contains(.delete("twice.")) == true)
    }

    @Test("empty old text against non-empty new text is entirely additions")
    func emptyOldIsAllAdditions() {
        let diff = SceneDiff.diff(old: "", new: "New content.")
        #expect(diff.contains { $0.kind == .added && $0.newText == "New content." })
    }

    @Test("multiple paragraphs changing at once each get their own row")
    func multipleChangedParagraphsEachGetOwnRow() {
        let old = "First.\n\nSecond.\n\nThird."
        let new = "First changed.\n\nSecond.\n\nThird changed."
        let diff = SceneDiff.diff(old: old, new: new)

        let modifiedRows = diff.filter { $0.kind == .modified }
        #expect(modifiedRows.count == 2)
        #expect(diff.contains { $0.kind == .unchanged && $0.oldText == "Second." })
    }
}
