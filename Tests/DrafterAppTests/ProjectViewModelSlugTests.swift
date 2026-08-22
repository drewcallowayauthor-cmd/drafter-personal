import Testing
@testable import DrafterApp

@Suite("ProjectViewModel.slug")
struct ProjectViewModelSlugTests {
    @Test("matches §5.2's example exactly")
    func matchesDesignDocExample() {
        #expect(ProjectViewModel.slug(for: "Last Call") == "last-call")
    }

    @Test("collapses runs of punctuation into a single hyphen")
    func collapsesPunctuationRuns() {
        #expect(ProjectViewModel.slug(for: "Book: A Novel!!") == "book-a-novel")
    }

    @Test("trims leading and trailing punctuation")
    func trimsLeadingAndTrailingPunctuation() {
        #expect(ProjectViewModel.slug(for: "  -Hello World-  ") == "hello-world")
    }

    @Test("a title with no letters or numbers falls back to a default")
    func emptyResultFallsBackToDefault() {
        #expect(ProjectViewModel.slug(for: "***") == "untitled")
    }
}
