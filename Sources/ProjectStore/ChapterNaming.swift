import Foundation

/// Suggests a default title for a new chapter, so "New Chapter" doesn't start blank.
public enum ChapterNaming {
    /// One past the highest `"Chapter N"` among `existingDisplayNames`, or `"Chapter 1"`
    /// if there are none. Non-numbered chapters (Prologue, Epilogue, custom titles) are
    /// ignored rather than counted, so they don't shift or break the sequence.
    public static func nextChapterTitle(existingDisplayNames: [String]) -> String {
        let numbers = existingDisplayNames.compactMap(chapterNumber(in:))
        return "Chapter \((numbers.max() ?? 0) + 1)"
    }

    private static func chapterNumber(in displayName: String) -> Int? {
        guard let range = displayName.range(
            of: #"^chapter\s+(\d+)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let digits = displayName[range].drop { !$0.isNumber }
        return Int(digits)
    }
}
