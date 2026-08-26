import Testing
@testable import ProjectStore

@Suite("ChapterNaming")
struct ChapterNamingTests {
    @Test("suggests Chapter 1 for a fresh project")
    func suggestsFirstChapter() {
        #expect(ChapterNaming.nextChapterTitle(existingDisplayNames: []) == "Chapter 1")
    }

    @Test("suggests one past the highest existing chapter number")
    func suggestsNextNumber() {
        let title = ChapterNaming.nextChapterTitle(existingDisplayNames: ["Chapter 1", "Chapter 2"])
        #expect(title == "Chapter 3")
    }

    @Test("ignores gaps and out-of-order numbering, using the max rather than the count")
    func usesMaxNotCount() {
        let title = ChapterNaming.nextChapterTitle(existingDisplayNames: ["Chapter 1", "Chapter 5"])
        #expect(title == "Chapter 6")
    }

    @Test("prologue and epilogue don't count toward or interrupt the sequence")
    func ignoresNonNumberedChapters() {
        let title = ChapterNaming.nextChapterTitle(
            existingDisplayNames: ["Prologue", "Chapter 1", "Chapter 2", "Epilogue"]
        )
        #expect(title == "Chapter 3")
    }

    @Test("a custom-titled chapter doesn't count toward or interrupt the sequence")
    func ignoresCustomTitles() {
        let title = ChapterNaming.nextChapterTitle(existingDisplayNames: ["Chapter 1", "The Storm", "Chapter 2"])
        #expect(title == "Chapter 3")
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        let title = ChapterNaming.nextChapterTitle(existingDisplayNames: ["chapter 1"])
        #expect(title == "Chapter 2")
    }
}
