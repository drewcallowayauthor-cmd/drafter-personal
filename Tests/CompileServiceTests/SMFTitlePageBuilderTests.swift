import Foundation
import Testing
import ProjectStore
@testable import CompileService

@Suite("SMFTitlePageBuilder")
struct SMFTitlePageBuilderTests {
    private func metadata(
        title: String = "The Long Way Home",
        author: String = "Jane K. Doe-Smith",
        manuscript: ProjectMetadata.Manuscript = ProjectMetadata.Manuscript()
    ) -> ProjectMetadata {
        ProjectMetadata(title: title, author: author, copyrightYear: 2026, manuscript: manuscript)
    }

    @Test("rounds word count to nearest 100")
    func roundsWordCount() {
        #expect(SMFTitlePageBuilder.roundedWordCount(38_142) == 38_100)
        #expect(SMFTitlePageBuilder.roundedWordCount(38_150) == 38_200)
        #expect(SMFTitlePageBuilder.roundedWordCount(49) == 0)
        #expect(SMFTitlePageBuilder.roundedWordCount(50) == 100)
    }

    @Test("word count appears with a thousands separator")
    func wordCountThousandsSeparator() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(), wordCount: 38_142)
        #expect(output.contains("38,100 words."))
    }

    @Test("title and byline are always present")
    func titleAndByline() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(), wordCount: 1_000)
        #expect(output.contains("SMFTitle"))
        #expect(output.contains("THE LONG WAY HOME"))
        #expect(output.contains("SMFByline"))
        #expect(output.contains("by Jane K. Doe-Smith"))
    }

    @Test("title is always uppercased on the title page")
    func titleIsUppercased() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(title: "the long way home"), wordCount: 1_000)
        #expect(output.contains("THE LONG WAY HOME"))
    }

    @Test("omits phone/email/agent lines when empty")
    func omitsEmptyOptionalLines() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(), wordCount: 1_000)
        #expect(!output.contains("("))
    }

    @Test("includes phone/email/agent lines when present")
    func includesFilledOptionalLines() {
        let manuscript = ProjectMetadata.Manuscript(
            address: "123 Main St",
            phone: "555-1234",
            email: "jane@example.com",
            agentName: "Pat Agent",
            agentAddress: "456 Agency Rd"
        )
        let output = SMFTitlePageBuilder.build(metadata: metadata(manuscript: manuscript), wordCount: 1_000)
        #expect(output.contains("123 Main St"))
        #expect(output.contains("555-1234"))
        #expect(output.contains("jane@example.com"))
        #expect(output.contains("(Pat Agent)"))
        #expect(output.contains("(456 Agency Rd)"))
    }

    @Test("ampersand and quote in author/title get XML-escaped")
    func escapesSpecialCharacters() {
        let output = SMFTitlePageBuilder.build(
            metadata: metadata(title: "Salt & \"Sea\"", author: "A & B"),
            wordCount: 1_000
        )
        #expect(output.contains("SALT &amp; &quot;SEA&quot;"))
        #expect(output.contains("A &amp; B"))
        #expect(!output.contains("SALT & \"SEA\""))
    }

    @Test("apostrophe in title is left as a literal character")
    func apostropheIsNotMangled() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(title: "It's Complicated"), wordCount: 1_000)
        #expect(output.contains("IT'S COMPLICATED"))
    }

    @Test("ends with a section break so the title page numbers separately from the manuscript body")
    func endsWithSectionBreak() {
        let output = SMFTitlePageBuilder.build(metadata: metadata(), wordCount: 1_000)
        #expect(output.contains("<w:sectPr>"))
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("```"))
        let sectPrIndex = output.range(of: "<w:sectPr>")!.lowerBound
        let bylineIndex = output.range(of: "SMFByline")!.lowerBound
        #expect(bylineIndex < sectPrIndex)
    }

    @Test("derives last name from a multi-word author name")
    func lastNameHeuristic() {
        #expect(SMFTitlePageBuilder.lastName(of: "Jane K. Doe-Smith") == "Doe-Smith")
        #expect(SMFTitlePageBuilder.lastName(of: "Cher") == "Cher")
    }

    @Test("produces well-formed XML when wrapped in a root element")
    func producesWellFormedXML() throws {
        let output = SMFTitlePageBuilder.build(metadata: metadata(), wordCount: 38_142)
        let inner = output
            .replacingOccurrences(of: "```{=openxml}\n", with: "")
            .replacingOccurrences(of: "\n```", with: "")
        let wrapped = "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(inner)</root>"
        let data = Data(wrapped.utf8)
        #expect(throws: Never.self) {
            try XMLDocument(data: data, options: [])
        }
    }
}
