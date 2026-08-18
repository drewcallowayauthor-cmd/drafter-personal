import AppKit
import Testing
@testable import DrafterApp

@MainActor
@Suite("MarkdownSyntaxHighlighter")
struct MarkdownSyntaxHighlighterTests {
    private let baseFont = NSFont.systemFont(ofSize: 15)

    @Test("italic content gets an italic font while its markers stay the base font")
    func italicContentGetsItalicFont() {
        let text = "It was *never* going to work."
        let storage = NSTextStorage(string: text)

        MarkdownSyntaxHighlighter.applyAttributes(to: storage, baseFont: baseFont)

        let contentRange = (text as NSString).range(of: "never")
        let contentFont = storage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont
        #expect(contentFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)

        let markerLocation = (text as NSString).range(of: "never").location - 1
        let markerFont = storage.attribute(.font, at: markerLocation, effectiveRange: nil) as? NSFont
        #expect(markerFont?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }

    @Test("bold markers are visually dimmed but still present in the string")
    func boldMarkersAreDimmedNotRemoved() {
        let text = "This is **important**."
        let storage = NSTextStorage(string: text)

        MarkdownSyntaxHighlighter.applyAttributes(to: storage, baseFont: baseFont)

        #expect(storage.string == text)
        let markerLocation = (text as NSString).range(of: "**important**").location
        let color = storage.attribute(.foregroundColor, at: markerLocation, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.tertiaryLabelColor)
    }

    @Test("plain prose is left at the base font throughout")
    func plainProseStaysBaseFont() {
        let text = "Just ordinary prose."
        let storage = NSTextStorage(string: text)

        MarkdownSyntaxHighlighter.applyAttributes(to: storage, baseFont: baseFont)

        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font == baseFont)
    }

    @Test("re-applying after an edit reflects the new content, not stale attributes")
    func reapplyingReflectsEditedContent() {
        let storage = NSTextStorage(string: "*italic*")
        MarkdownSyntaxHighlighter.applyAttributes(to: storage, baseFont: baseFont)

        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "plain text now")
        MarkdownSyntaxHighlighter.applyAttributes(to: storage, baseFont: baseFont)

        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }
}
