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
        #expect(FrontBackMatterTemplate.titlePage.section == .front)
        #expect(FrontBackMatterTemplate.copyright.section == .front)
        #expect(FrontBackMatterTemplate.dedication.section == .front)
        #expect(FrontBackMatterTemplate.reviewAsk.section == .back)
        #expect(FrontBackMatterTemplate.aboutTheAuthor.section == .back)
        #expect(FrontBackMatterTemplate.newsletter.section == .back)
    }

    @Test("only Title Page and About the Author show their own heading text on the page")
    func showsHeadingOnPageMatchesHiddenHeadingClass() {
        #expect(FrontBackMatterTemplate.titlePage.showsHeadingOnPage)
        #expect(FrontBackMatterTemplate.aboutTheAuthor.showsHeadingOnPage)
        #expect(!FrontBackMatterTemplate.copyright.showsHeadingOnPage)
        #expect(!FrontBackMatterTemplate.dedication.showsHeadingOnPage)
        #expect(!FrontBackMatterTemplate.reviewAsk.showsHeadingOnPage)
        #expect(!FrontBackMatterTemplate.newsletter.showsHeadingOnPage)
    }

    @Test("filenames match the reference EPUB's front/back matter order")
    func filenamesMatchExampleLayout() {
        #expect(FrontBackMatterTemplate.titlePage.filename == "01 Title Page.md")
        #expect(FrontBackMatterTemplate.copyright.filename == "02 Copyright.md")
        #expect(FrontBackMatterTemplate.dedication.filename == "03 Dedication.md")
        #expect(FrontBackMatterTemplate.reviewAsk.filename == "01 A Note From the Author.md")
        #expect(FrontBackMatterTemplate.newsletter.filename == "02 Newsletter.md")
        #expect(FrontBackMatterTemplate.aboutTheAuthor.filename == "03 About the Author.md")
    }

    @Test("title page includes a large-format heading anchor, a centered subtitle, and a byline author")
    func titlePageContent() {
        let content = FrontBackMatterTemplate.titlePage.content(for: metadata)
        #expect(content.hasPrefix("# The Last Shift {.title-page-heading #title-page}\n\n::: {.centered-page}\n"))
        #expect(content.contains("A Novel"))
        #expect(content.contains("[Tim Fleet]{.byline}"))
        #expect(content.hasSuffix(":::"))
    }

    @Test("title page omits the subtitle line entirely when there is no subtitle")
    func titlePageOmitsEmptySubtitle() {
        let noSubtitle = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let content = FrontBackMatterTemplate.titlePage.content(for: noSubtitle)
        #expect(content.contains("A Novel") == false)
        #expect(content.contains("[Tim Fleet]{.byline}"))
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
        #expect(FrontBackMatterTemplate.matching(filename: "01 Title Page.md") == .titlePage)
        #expect(FrontBackMatterTemplate.matching(filename: "03 About the Author.md") == .aboutTheAuthor)
        #expect(FrontBackMatterTemplate.matching(filename: "05 Some Custom Note.md") == nil)
    }

    @Test("every template's anchor ID appears in its own heading, so Contents links actually resolve")
    func anchorsAppearInOwnHeading() {
        for template in FrontBackMatterTemplate.allCases {
            let content = template.content(for: metadata)
            #expect(content.contains("#\(template.anchorID)}"), "\(template) is missing its own anchor")
        }
    }

    @Test("every template's content includes the author's name")
    func allTemplatesReferenceAuthorOrTitleReasonably() {
        for template in FrontBackMatterTemplate.allCases {
            let content = template.content(for: metadata)
            #expect(!content.isEmpty)
        }
    }
}
