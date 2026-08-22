import Foundation

/// The centered `* * *` a submission manuscript ends on, right after the last line of
/// body text — same raw-OOXML-splice technique `SMFTitlePageBuilder` uses, since a
/// plain markdown paragraph would inherit the body's left-aligned, first-line-indented
/// style rather than being centered. Requires the `SMFEndMark` paragraph style to
/// exist in the reference.docx passed to pandoc.
public enum SMFEndOfManuscriptMarker {
    public static func append(to manuscriptMarkdown: String) -> String {
        manuscriptMarkdown + "\n\n" + marker
    }

    private static var marker: String {
        "```{=openxml}\n<w:p><w:pPr><w:pStyle w:val=\"SMFEndMark\" /></w:pPr><w:r><w:t>* * *</w:t></w:r></w:p>\n```"
    }
}
