import Foundation
import Testing
@testable import DrafterApp

@Suite("MarkerWrapping")
struct MarkerWrappingTests {
    @Test("wraps a selection in italic markers and selects the inner text, not the markers")
    func wrapsSelectionInItalicMarkers() {
        let text = "It was never going to work."
        let selection = (text as NSString).range(of: "never")

        let result = MarkerWrapping.wrap(text: text, selectedRange: selection, marker: "*")

        #expect(result.replacementText == "*never*")
        #expect(result.replacementRange == selection)
        #expect(result.newSelectedRange == NSRange(location: selection.location + 1, length: selection.length))
    }

    @Test("wraps a selection in bold markers, accounting for the two-character marker")
    func wrapsSelectionInBoldMarkers() {
        let text = "This is important."
        let selection = (text as NSString).range(of: "important")

        let result = MarkerWrapping.wrap(text: text, selectedRange: selection, marker: "**")

        #expect(result.replacementText == "**important**")
        #expect(result.newSelectedRange == NSRange(location: selection.location + 2, length: selection.length))
    }

    @Test("with no selection, inserts a paired marker with the caret placed between them")
    func insertsPairedMarkerAtCaretWithNoSelection() {
        let caret = NSRange(location: 5, length: 0)

        let result = MarkerWrapping.wrap(text: "hello world", selectedRange: caret, marker: "*")

        #expect(result.replacementText == "**")
        #expect(result.replacementRange == caret)
        #expect(result.newSelectedRange == NSRange(location: 6, length: 0))
    }

    @Test("with no selection, bold inserts two pairs of asterisks with the caret in the middle")
    func insertsPairedBoldMarkerAtCaret() {
        let caret = NSRange(location: 0, length: 0)

        let result = MarkerWrapping.wrap(text: "", selectedRange: caret, marker: "**")

        #expect(result.replacementText == "****")
        #expect(result.newSelectedRange == NSRange(location: 2, length: 0))
    }
}
