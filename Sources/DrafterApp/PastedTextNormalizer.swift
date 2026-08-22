import Foundation

/// Pure computation for `TypewriterTextView.paste(_:)` (§8.3): what a pasted string
/// should become before insertion. Kept separate from the `NSTextView`/`NSPasteboard`
/// glue so the actual normalization is testable without a live text view, mirroring
/// `MarkerWrapping`.
public enum PastedTextNormalizer {
    public static func normalize(_ text: String) -> String {
        promoteLoneNewlinesToParagraphBreaks(unifyLineEndings(text))
    }

    /// Every line-ending variant a source app might hand back — `\r\n`, bare `\r`
    /// (classic Mac line endings, still produced by some PDF/RTF-to-plain-text
    /// conversions), and the Unicode line/paragraph separators U+2028/U+2029 —
    /// collapses to a plain `\n`. A paste landing as `\r`-only looked fine in the live
    /// `NSTextView` (which treats `\r`/`\n`/U+2028/U+2029 all as paragraph breaks for
    /// layout) but silently failed to register as a break anywhere downstream that
    /// specifically checks for `\n` (scene front-matter parsing, word counting).
    private static func unifyLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    /// Drafter's own scene files separate paragraphs with a *blank line* (`\n\n`) —
    /// confirmed directly against a real scene file on disk, not assumed — the same
    /// convention pandoc's markdown reader expects for a real paragraph break (a lone
    /// `\n` is just an insignificant soft break there, collapsed on compile). Many
    /// sources hand back one `\n` per paragraph with no blank line instead — Scrivener
    /// RTF's plain-text conversion does exactly this (verified directly against a real
    /// paste: every paragraph on its own line, single `\n` between them, confirmed via
    /// `NSPasteboard.general.string(forType: .string)`). Pasted verbatim, that reads
    /// as a wall of text in the editor even though every character survived intact —
    /// the paragraph breaks are real, just not the ones this app's own format uses. A
    /// lone `\n` — one with a non-newline character on both sides, i.e. not already
    /// part of an existing `\n\n`+ blank-line group — gets promoted to a real
    /// paragraph break. Existing blank-line groups of any size are left untouched (the
    /// lookbehind/lookahead both fail on every `\n` inside one), so this never
    /// compounds a document that already uses this app's own convention correctly.
    private static func promoteLoneNewlinesToParagraphBreaks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\n)\n(?!\n)") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n\n")
    }
}
