import Foundation

/// Renders a chapter heading from `compile.chapterTitleFormat` (§9.1). Tokens: `{n}`
/// (1-based index), `{n_word}` (`One`, `Two`, …), `{title}` (folder name minus prefix).
/// `"none"` emits no heading at all.
public enum ChapterHeadingFormatter {
    /// A chapter titled exactly one of these (case-insensitively — a chapter's title
    /// is just its folder name, and folks type "prologue" as often as "Prologue")
    /// stands on its own: its heading is the title as written, never run through
    /// `chapterTitleFormat`'s `{n}`/`{n_word}` tokens, and — in `ManuscriptAssembler`
    /// — it doesn't consume a number, so a Prologue before Chapter 1 never bumps it
    /// to Chapter 2.
    public static let unnumberedTitles: Set<String> = ["prologue", "epilogue"]

    public static func isUnnumbered(title: String) -> Bool {
        unnumberedTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func heading(format: String, index: Int, title: String) -> String? {
        guard format != "none" else { return nil }
        if isUnnumbered(title: title) { return title }
        return format
            .replacingOccurrences(of: "{n_word}", with: NumberSpeller.spell(index))
            .replacingOccurrences(of: "{n}", with: String(index))
            .replacingOccurrences(of: "{title}", with: title)
    }

    /// A stable anchor ID for this chapter's heading — used to link to it from
    /// `EPUBTableOfContentsGenerator`'s Contents page without needing to reproduce
    /// pandoc's own heading-slug algorithm (which derives an ID from the *rendered*
    /// heading text — fragile to reproduce exactly since it depends on
    /// `chapterTitleFormat`). `index` alone is enough for a numbered chapter, since
    /// it's already unique; an unnumbered one (Prologue/Epilogue) uses its slugified
    /// title instead — index isn't unique across unnumbered chapters (they don't
    /// advance it), but two Prologues in one manuscript isn't a case worth the extra
    /// bookkeeping to disambiguate.
    public static func anchorID(index: Int, title: String) -> String {
        isUnnumbered(title: title) ? slugify(title) : "chapter-\(index)"
    }

    /// Lowercases, maps anything that isn't a letter/digit to a hyphen, and collapses
    /// runs of hyphens — good enough for the plain-ASCII titles chapters realistically
    /// have (never shown to the reader, only used as an anchor).
    static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let mapped = String(
            lowered.unicodeScalars.map { scalar in
                (CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-") ? Character(scalar) : " "
            }
        )
        let collapsed = mapped.split(separator: " ").joined(separator: "-")
        return collapsed.isEmpty ? "section" : collapsed
    }
}

/// English number-to-words, only as far as a chapter count could plausibly go.
enum NumberSpeller {
    private static let ones = [
        "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
        "Seventeen", "Eighteen", "Nineteen"
    ]
    private static let tens = [
        "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"
    ]

    static func spell(_ n: Int) -> String {
        guard n > 0 else { return String(n) }
        if n < 20 { return ones[n] }
        if n < 100 {
            let (ten, one) = (n / 10, n % 10)
            return one == 0 ? tens[ten] : "\(tens[ten])-\(ones[one])"
        }
        if n < 1000 {
            let (hundred, remainder) = (n / 100, n % 100)
            let prefix = "\(ones[hundred]) Hundred"
            return remainder == 0 ? prefix : "\(prefix) \(spell(remainder))"
        }
        return String(n)
    }
}
