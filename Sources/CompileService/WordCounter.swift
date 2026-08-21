import Foundation

/// Appendix B: count markdown source with YAML front matter, `#` markers, emphasis markers,
/// scene separators, and HTML comments removed; split on whitespace; hyphenated compounds
/// count as one; standalone punctuation tokens are excluded. Pure function — no I/O — so
/// it's cheap to exhaustively unit test.
public enum WordCounter {
    public static func count(_ markdown: String, sceneSeparator: String = "* * *") -> Int {
        // Normalize CRLF up front: every line-based comparison below (front-matter
        // fences, scene-separator lines) compares against a bare "\n"-split line, which
        // a CRLF-terminated source would fail (trailing "\r" on every line), silently
        // leaving front matter unstripped and separators uncollapsed.
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var text = stripFrontMatter(normalized)
        text = stripHTMLComments(text)

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces) != sceneSeparator }
        text = lines.joined(separator: "\n")

        text = text.replacingOccurrences(of: "#", with: " ")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "*", with: "")

        let punctuationOnly = CharacterSet.punctuationCharacters.union(.symbols)
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
            .filter { token in
                !token.unicodeScalars.allSatisfy { punctuationOnly.contains($0) }
            }
        return tokens.count
    }

    private static func stripFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---") else { return markdown }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return markdown }
        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0 == "---" }) else {
            return markdown
        }
        return lines[(closingIndex + 1)...].joined(separator: "\n")
    }

    private static func stripHTMLComments(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators]) else {
            return markdown
        }
        let range = NSRange(markdown.startIndex..., in: markdown)
        return regex.stringByReplacingMatches(in: markdown, range: range, withTemplate: "")
    }
}
