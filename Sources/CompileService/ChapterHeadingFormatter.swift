import Foundation

/// Renders a chapter heading from `compile.chapterTitleFormat` (§9.1). Tokens: `{n}`
/// (1-based index), `{n_word}` (`One`, `Two`, …), `{title}` (folder name minus prefix).
/// `"none"` emits no heading at all.
public enum ChapterHeadingFormatter {
    public static func heading(format: String, index: Int, title: String) -> String? {
        guard format != "none" else { return nil }
        return format
            .replacingOccurrences(of: "{n_word}", with: NumberSpeller.spell(index))
            .replacingOccurrences(of: "{n}", with: String(index))
            .replacingOccurrences(of: "{title}", with: title)
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
