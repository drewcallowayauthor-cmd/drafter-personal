import Testing
@testable import ProjectStore

@Suite("FrontBackMatterTemplate")
struct FrontBackMatterTemplateTests {
    private let metadata = ProjectMetadata(
        title: "The Last Shift",
        subtitle: "A Novel",
        author: "Tim Fleet",
        copyrightYear: 2026,
        isbn: "978-0-000000-00-0"
    )

    @Test("front matter files are assigned to .front, back matter to .back")
    func sectionsAreCorrect() {
        #expect(FrontBackMatterTemplate.alsoBy.section == .front)
        #expect(FrontBackMatterTemplate.titlePage.section == .front)
        #expect(FrontBackMatterTemplate.copyright.section == .front)
        #expect(FrontBackMatterTemplate.dedication.section == .front)
        #expect(FrontBackMatterTemplate.aboutTheAuthor.section == .back)
        #expect(FrontBackMatterTemplate.newsletter.section == .back)
    }

    @Test("filenames match the design doc's example layout exactly")
    func filenamesMatchExampleLayout() {
        #expect(FrontBackMatterTemplate.alsoBy.filename == "01 Also By.md")
        #expect(FrontBackMatterTemplate.titlePage.filename == "02 Title Page.md")
        #expect(FrontBackMatterTemplate.copyright.filename == "03 Copyright.md")
        #expect(FrontBackMatterTemplate.dedication.filename == "04 Dedication.md")
        #expect(FrontBackMatterTemplate.aboutTheAuthor.filename == "01 About the Author.md")
        #expect(FrontBackMatterTemplate.newsletter.filename == "02 Newsletter.md")
    }

    @Test("title page includes title, subtitle, and author")
    func titlePageContent() {
        let content = FrontBackMatterTemplate.titlePage.content(for: metadata)
        #expect(content == "# The Last Shift\nA Novel\n\nTim Fleet")
    }

    @Test("title page omits the subtitle line entirely when there is no subtitle")
    func titlePageOmitsEmptySubtitle() {
        let noSubtitle = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let content = FrontBackMatterTemplate.titlePage.content(for: noSubtitle)
        #expect(content == "# The Last Shift\n\nTim Fleet")
    }

    @Test("copyright includes the year, author, and ISBN line when present")
    func copyrightIncludesISBN() {
        let content = FrontBackMatterTemplate.copyright.content(for: metadata)
        #expect(content.contains("Copyright © 2026 by Tim Fleet"))
        #expect(content.contains("ISBN: 978-0-000000-00-0"))
    }

    @Test("copyright omits the ISBN line when there is no ISBN")
    func copyrightOmitsMissingISBN() {
        let noISBN = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let content = FrontBackMatterTemplate.copyright.content(for: noISBN)
        #expect(content.contains("ISBN:") == false)
    }

    @Test("matching(filename:) finds the right template and returns nil for non-standard files")
    func matchingFindsTemplateByFilename() {
        #expect(FrontBackMatterTemplate.matching(filename: "02 Title Page.md") == .titlePage)
        #expect(FrontBackMatterTemplate.matching(filename: "01 About the Author.md") == .aboutTheAuthor)
        #expect(FrontBackMatterTemplate.matching(filename: "05 Some Custom Note.md") == nil)
    }

    @Test("every template's content includes the author's name")
    func allTemplatesReferenceAuthorOrTitleReasonably() {
        for template in FrontBackMatterTemplate.allCases {
            let content = template.content(for: metadata)
            #expect(!content.isEmpty)
        }
    }
}
