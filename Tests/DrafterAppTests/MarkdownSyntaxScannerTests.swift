import Foundation
import Testing
@testable import DrafterApp

@Suite("MarkdownSyntaxScanner")
struct MarkdownSyntaxScannerTests {
    @Test("finds italic markers and content")
    func findsItalic() {
        let ranges = MarkdownSyntaxScanner.scan("It was *never* going to work.")
        let nsText = "It was *never* going to work." as NSString

        #expect(ranges.contains(
            SyntaxRange(range: nsText.range(of: "*", range: NSRange(location: 7, length: 1)), kind: .italicMarker)
        ))
        #expect(ranges.contains(SyntaxRange(range: nsText.range(of: "never"), kind: .italicContent)))
    }

    @Test("finds bold markers and content")
    func findsBold() {
        let text = "This is **important**."
        let ranges = MarkdownSyntaxScanner.scan(text)
        let nsText = text as NSString

        #expect(ranges.contains(SyntaxRange(range: nsText.range(of: "important"), kind: .boldContent)))
        #expect(ranges.contains { $0.kind == .boldMarker })
        #expect(ranges.filter { $0.kind == .boldMarker }.count == 2)
    }

    @Test("bold takes precedence over italic so ** isn't read as nested *")
    func boldTakesPrecedenceOverItalic() {
        let text = "This is **important**."
        let ranges = MarkdownSyntaxScanner.scan(text)

        #expect(ranges.contains { $0.kind == .italicMarker } == false)
        #expect(ranges.contains { $0.kind == .italicContent } == false)
    }

    @Test("finds a header marker and content")
    func findsHeader() {
        let text = "# Last Call"
        let ranges = MarkdownSyntaxScanner.scan(text)
        let nsText = text as NSString

        #expect(ranges.contains(SyntaxRange(range: nsText.range(of: "# "), kind: .headerMarker)))
        #expect(ranges.contains(SyntaxRange(range: nsText.range(of: "Last Call"), kind: .headerContent)))
    }

    @Test("plain prose with no markdown produces no ranges")
    func plainProseProducesNoRanges() {
        #expect(MarkdownSyntaxScanner.scan("Just ordinary prose, nothing special.").isEmpty)
    }

    @Test("multiple italic spans in one line are all found")
    func multipleItalicSpans() {
        let text = "*First* and *second* are both italic."
        let ranges = MarkdownSyntaxScanner.scan(text)
        #expect(ranges.filter { $0.kind == .italicContent }.count == 2)
    }

    @Test("a lone asterisk with no closing pair produces no italic range")
    func loneAsteriskProducesNoMatch() {
        let ranges = MarkdownSyntaxScanner.scan("This * is not italic.")
        #expect(ranges.isEmpty)
    }
}
