import Foundation

/// §8.3 point 6: "⌘I / ⌘B wrap selection or insert paired markers." Pure computation —
/// given the current text, selection, and marker (`*` or `**`), what replacement to make
/// and where the selection should land afterward. Kept separate from the `NSTextView`
/// glue (`TypewriterTextView`'s action methods) so the actual decision logic is testable
/// without a live text view.
public enum MarkerWrapping {
    public struct Result: Equatable {
        public let replacementText: String
        public let replacementRange: NSRange
        public let newSelectedRange: NSRange
    }

    /// With a selection: wraps it in markers and keeps the inner text selected (not the
    /// markers), so repeated typing replaces the word, not the whole markered span.
    /// With no selection: inserts a paired marker with the caret placed between them,
    /// ready to type into.
    public static func wrap(text: String, selectedRange: NSRange, marker: String) -> Result {
        let markerLength = (marker as NSString).length

        guard selectedRange.length > 0 else {
            let replacement = marker + marker
            let caret = selectedRange.location + markerLength
            return Result(
                replacementText: replacement,
                replacementRange: selectedRange,
                newSelectedRange: NSRange(location: caret, length: 0)
            )
        }

        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)
        let replacement = marker + selectedText + marker
        let newRange = NSRange(location: selectedRange.location + markerLength, length: selectedRange.length)
        return Result(replacementText: replacement, replacementRange: selectedRange, newSelectedRange: newRange)
    }
}
