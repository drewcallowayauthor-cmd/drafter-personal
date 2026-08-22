import Foundation
import ProjectStore

/// Builds the Standard Manuscript Format title page as a raw-OOXML markdown block
/// (pandoc's `raw_attribute` extension splices this straight into document.xml),
/// since pandoc's own built-in title-block mechanism can't produce the
/// contact-block-top-left / word-count-top-right / centered-title layout real
/// submission manuscripts use. Requires `SMFContact`/`SMFTitle`/`SMFByline`
/// paragraph styles to exist in the reference.docx passed to pandoc.
public enum SMFTitlePageBuilder {
    public static func build(metadata: ProjectMetadata, wordCount: Int) -> String {
        var lines: [String] = []

        // Contact block. First line carries the word count via a right tab stop on
        // the same paragraph (matches Shunn format), everything else optional and
        // only emitted if the user filled it in — no fake placeholder text.
        lines.append(contactParagraph(firstLine: metadata.author, wordCount: wordCount))
        if !metadata.manuscript.address.isEmpty {
            lines.append(contactParagraph(firstLine: metadata.manuscript.address))
        }
        if !metadata.manuscript.phone.isEmpty {
            lines.append(contactParagraph(firstLine: metadata.manuscript.phone))
        }
        if !metadata.manuscript.email.isEmpty {
            lines.append(contactParagraph(firstLine: metadata.manuscript.email))
        }
        let hasAgentInfo = !metadata.manuscript.agentName.isEmpty || !metadata.manuscript.agentAddress.isEmpty
        if hasAgentInfo {
            lines.append(contactParagraph(firstLine: ""))
            if !metadata.manuscript.agentName.isEmpty {
                lines.append(contactParagraph(firstLine: "(\(metadata.manuscript.agentName))"))
            }
            if !metadata.manuscript.agentAddress.isEmpty {
                lines.append(contactParagraph(firstLine: "(\(metadata.manuscript.agentAddress))"))
            }
        }

        lines.append(paragraph(style: "SMFTitle", text: metadata.title.uppercased()))
        lines.append(paragraph(style: "SMFByline", text: "by \(metadata.author)"))
        lines.append(sectionBreakParagraph())

        let body = lines.joined(separator: "\n")
        return "```{=openxml}\n\(body)\n```"
    }

    /// "Jane K. Doe-Smith" -> "Doe-Smith". Best-effort heuristic for the running
    /// header (§ DOCXExportCoordinator) — there's no separate structured last-name
    /// field anywhere in the app, `author` is one free-text string.
    public static func lastName(of fullName: String) -> String {
        fullName.split(separator: " ").last.map(String.init) ?? fullName
    }

    /// Shunn convention rounds the stated word count rather than giving an exact
    /// figure that will be stale the moment the author edits another scene.
    public static func roundedWordCount(_ count: Int) -> Int {
        Int((Double(count) / 100).rounded()) * 100
    }

    private static func contactParagraph(firstLine: String, wordCount: Int? = nil) -> String {
        var text = escape(firstLine)
        if let wordCount {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: roundedWordCount(wordCount)), number: .decimal)
            text += "\u{9}\(formatted) words."
        }
        return paragraph(style: "SMFContact", text: text, alreadyEscaped: true)
    }

    /// An empty paragraph whose `pPr` carries a `sectPr`, ending the title page as its
    /// own OOXML section (§ real Shunn-format `.docx` reference examined for this
    /// feature). A `sectPr` embedded in a paragraph's `pPr` describes the section that
    /// *ends* there, so this is what makes the manuscript body that follows start a new
    /// section — with no `headerReference` here at all, the title page shows no running
    /// header/page number, and the *next* section (the reference doc's own trailing
    /// `sectPr`, carrying `headerReference`/`pgNumType w:start="1"`) makes "Chapter One"
    /// page 1 rather than page 2. Page size/margins are repeated from the reference
    /// doc's section so the title page doesn't visibly resize before the break.
    private static func sectionBreakParagraph() -> String {
        """
        <w:p><w:pPr><w:sectPr><w:pgSz w:w="12240" w:h="15840" /><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0" /></w:sectPr></w:pPr></w:p>
        """
    }

    private static func paragraph(style: String, text: String, alreadyEscaped: Bool = false) -> String {
        let content = alreadyEscaped ? text : escape(text)
        // `\u{9}` (tab) inside the text becomes a literal <w:tab/> run break so the
        // SMFContact style's right tab stop actually applies.
        let runs = content.components(separatedBy: "\u{9}").map { "<w:r><w:t xml:space=\"preserve\">\($0)</w:t></w:r>" }
        let tabbedRuns = runs.enumerated().map { index, run in index == 0 ? run : "<w:r><w:tab/></w:r>\(run)" }.joined()
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\" /></w:pPr>\(tabbedRuns)</w:p>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
