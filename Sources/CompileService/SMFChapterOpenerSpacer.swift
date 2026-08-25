import Foundation

/// Pushes each chapter heading down the page with blank double-spaced lines (§ real
/// Shunn-format `.docx` reference examined for this feature) instead of the `Heading1`
/// style's own `spacing before` — Word (and Pages) don't apply a paragraph's "space
/// before" when that paragraph is the very first one on a page, so a page-break-before
/// heading with only `spacing before` set renders flush with the top margin. Real
/// blank paragraphs aren't affected by that quirk, which is how the reference
/// document — and every real manuscript — actually does it. DOCX-only: pandoc's own
/// heading handling is untouched, so print/EPUB (which don't have this problem, and
/// use their own template's chapter-opener spacing) don't get these paragraphs.
public enum SMFChapterOpenerSpacer {
    /// Matches `ManuscriptAssembler`'s generated `# Heading Text {.chapter-title
    /// #anchor-id}` lines exactly — the only headings `assembleManuscript` emits.
    private static let headingLinePattern = #"^# .+ \{\.chapter-title #[^}]+\}$"#

    public static func insertSpacing(into manuscriptMarkdown: String, blankLines: Int = 14) -> String {
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: headingLinePattern, options: [.anchorsMatchLines])
        let range = NSRange(manuscriptMarkdown.startIndex..., in: manuscriptMarkdown)
        let spacerBlock = spacerParagraphs(count: blankLines)
        let template = NSRegularExpression.escapedTemplate(for: spacerBlock) + "\n\n$0"
        return regex.stringByReplacingMatches(in: manuscriptMarkdown, options: [], range: range, withTemplate: template)
    }

    private static func spacerParagraphs(count: Int) -> String {
        let paragraphs = (0..<count).map { index in
            index == 0
                ? #"<w:p><w:pPr><w:pStyle w:val="ChapterSpacer" /><w:pageBreakBefore /></w:pPr></w:p>"#
                : #"<w:p><w:pPr><w:pStyle w:val="ChapterSpacer" /></w:pPr></w:p>"#
        }.joined()
        return "```{=openxml}\n\(paragraphs)\n```"
    }
}
