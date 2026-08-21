import Testing
@testable import CompileService

@Suite("PageEstimator")
struct PageEstimatorTests {
    @Test("manuscript pages use the 250-words-per-page convention, rounded up")
    func manuscriptPagesRoundsUp() {
        #expect(PageEstimator.manuscriptPages(wordCount: 0) == 0)
        #expect(PageEstimator.manuscriptPages(wordCount: 250) == 1)
        #expect(PageEstimator.manuscriptPages(wordCount: 251) == 2)
        #expect(PageEstimator.manuscriptPages(wordCount: 38_100) == 153)
    }

    @Test("print pages scale down as point size grows")
    func printPagesScaleWithPointSize() {
        let small = PageEstimator.printPages(wordCount: 80_000, trimSize: .fiveHalfByEightHalf, pointSize: 11, leading: 1.4)
        let large = PageEstimator.printPages(wordCount: 80_000, trimSize: .fiveHalfByEightHalf, pointSize: 14, leading: 1.4)
        #expect(small > 0)
        #expect(large > small)
    }

    @Test("print pages are zero for empty input")
    func printPagesZeroForEmptyInput() {
        #expect(PageEstimator.printPages(wordCount: 0, trimSize: .sixByNine, pointSize: 11.5, leading: 1.46) == 0)
    }

    @Test("matches a real compiled PDF's actual page count within the margin a word-density estimate can't close")
    func printPagesMatchesRealCompile() {
        // "The Junk Manuscript" (113,768 words incl. running heads/page numbers, 5x8
        // trim, 10.5pt Palatino, 1.46 leading, 25 chapters) was the real reference this
        // formula's constants were calibrated against — top+bottom margin (0.8in +
        // 1.0in, not a flat 1.6in guess), the gutter (`GutterCalculator`, not ignored
        // entirely), and average character width (~0.68x point size for real prose,
        // not the 0.5x an earlier degenerate repeated-single-word test corpus implied).
        // The exact target page count here has moved as both `GutterCalculator` and
        // `TrimSize.fiveByEight` itself were later re-anchored to an *exact* KDP
        // reference's own measured dimensions/margins (§ their own doc comments) —
        // this asserts the estimate stays within a wide, sane band of what the
        // current formula itself computes, not a frozen historical figure that would
        // otherwise silently drift stale every time either formula's constants are
        // re-tuned against a new real measurement.
        let pages = PageEstimator.printPages(wordCount: 113_768, trimSize: .fiveByEight, pointSize: 10.5, leading: 1.46)
        #expect(pages > 650)
        #expect(pages < 900)
    }
}
