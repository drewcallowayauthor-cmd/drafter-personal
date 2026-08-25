import Foundation

/// Post-processing pure-string helpers for the two things pandoc's `--reference-doc`
/// mechanism can't parameterize per-project: the running header's literal
/// author-lastname/title text (headers/footers are copied verbatim from the
/// reference doc, no metadata substitution), and swapping the body font between
/// Times New Roman and Courier New. `DOCXExportCoordinator` applies these to the
/// *generated output* docx's extracted `word/header1.xml` / `word/styles.xml` after
/// pandoc runs, since header1.xml in reference.docx only carries placeholder tokens.
public enum DOCXHeaderPatcher {
    static let authorLastNameToken = "AUTHORLASTNAME"
    static let titleToken = "MANUSCRIPTTITLE"

    public static func patchHeader(_ headerXML: String, authorLastName: String, title: String) -> String {
        headerXML
            .replacingOccurrences(of: authorLastNameToken, with: xmlEscape(authorLastName))
            .replacingOccurrences(of: titleToken, with: xmlEscape(title))
    }

    /// A no-op when `font` is already Times New Roman (the reference doc's default),
    /// so callers can call this unconditionally without a branch.
    public static func applyBodyFont(_ font: String, to stylesXML: String) -> String {
        guard font.caseInsensitiveCompare("Times New Roman") != .orderedSame else { return stylesXML }
        return stylesXML.replacingOccurrences(of: "Times New Roman", with: font)
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
