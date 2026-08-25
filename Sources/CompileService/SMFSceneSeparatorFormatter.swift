import Foundation

/// Replaces every standalone `compile.sceneSeparator` line with a centered raw-OOXML
/// paragraph, the same splice technique `SMFTitlePageBuilder`/`SMFChapterOpenerSpacer`
/// use — pandoc's markdown parser treats a bare separator line as *structure*, not
/// literal text, in ways that silently destroy it: `"* * *"` alone on a line is a
/// CommonMark thematic break (pandoc emits an actual horizontal-rule drawing object in
/// the `.docx`, not text), and `"#"` alone is a valid empty ATX heading (renders as a
/// blank `Heading1` paragraph — the separator vanishes entirely). Splicing it in as raw
/// OOXML sidesteps markdown parsing altogether, and picks up manuscript-standard
/// centering as a side effect. Requires the `SMFSceneBreak` paragraph style to exist in
/// the reference.docx passed to pandoc.
public enum SMFSceneSeparatorFormatter {
    public static func format(_ manuscriptMarkdown: String, separator: String) -> String {
        guard !separator.isEmpty else { return manuscriptMarkdown }
        let escapedPattern = NSRegularExpression.escapedPattern(for: separator)
        guard let regex = try? NSRegularExpression(pattern: "^\(escapedPattern)$", options: [.anchorsMatchLines]) else {
            return manuscriptMarkdown
        }
        let range = NSRange(manuscriptMarkdown.startIndex..., in: manuscriptMarkdown)
        let template = NSRegularExpression.escapedTemplate(for: separatorParagraph(text: separator))
        return regex.stringByReplacingMatches(in: manuscriptMarkdown, options: [], range: range, withTemplate: template)
    }

    private static func separatorParagraph(text: String) -> String {
        "```{=openxml}\n<w:p><w:pPr><w:pStyle w:val=\"SMFSceneBreak\" /></w:pPr><w:r><w:t xml:space=\"preserve\">"
            + "\(xmlEscape(text))</w:t></w:r></w:p>\n```"
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
