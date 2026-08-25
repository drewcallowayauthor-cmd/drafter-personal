import Foundation

/// A range of the scene's source text that the editor should render specially (§8.3
/// point 5: "render `*italic*` in actual italic while leaving asterisks visible but
/// dimmed. Same for `**bold**` and `#`."). Pure text scanning, no AppKit — the marker
/// characters stay in the file untouched, this only says how to *display* them.
public struct SyntaxRange: Equatable {
    public enum Kind: Equatable {
        case boldMarker
        case boldContent
        case italicMarker
        case italicContent
        case headerMarker
        case headerContent
    }

    public let range: NSRange
    public let kind: Kind
}

public enum MarkdownSyntaxScanner {
    // swiftlint:disable force_try
    /// Drafter's markdown dialect is deliberately tiny (§4.6) and not expected to
    /// nest, so these patterns favor simplicity over handling every pathological case.
    private static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*([^\\n*]+?)\\*\\*")
    private static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^\\n*]+?)\\*(?!\\*)")
    private static let headerPattern = try! NSRegularExpression(
        pattern: "^(#{1,6}[ \\t]+)(.*)$",
        options: [.anchorsMatchLines]
    )
    // swiftlint:enable force_try

    public static func scan(_ text: String) -> [SyntaxRange] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var results: [SyntaxRange] = []
        var claimed = IndexSet()

        for match in boldPattern.matches(in: text, range: fullRange) where match.numberOfRanges == 2 {
            let full = match.range
            let inner = match.range(at: 1)
            results.append(SyntaxRange(range: NSRange(location: full.location, length: 2), kind: .boldMarker))
            results.append(SyntaxRange(range: inner, kind: .boldContent))
            results.append(
                SyntaxRange(range: NSRange(location: full.location + full.length - 2, length: 2), kind: .boldMarker)
            )
            claimed.insert(integersIn: full.location..<(full.location + full.length))
        }

        for match in italicPattern.matches(in: text, range: fullRange) where match.numberOfRanges == 2 {
            let full = match.range
            guard !claimed.contains(full.location) else { continue }
            let inner = match.range(at: 1)
            results.append(SyntaxRange(range: NSRange(location: full.location, length: 1), kind: .italicMarker))
            results.append(SyntaxRange(range: inner, kind: .italicContent))
            results.append(
                SyntaxRange(range: NSRange(location: full.location + full.length - 1, length: 1), kind: .italicMarker)
            )
        }

        for match in headerPattern.matches(in: text, range: fullRange) where match.numberOfRanges == 3 {
            results.append(SyntaxRange(range: match.range(at: 1), kind: .headerMarker))
            results.append(SyntaxRange(range: match.range(at: 2), kind: .headerContent))
        }

        return results
    }
}
