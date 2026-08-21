import Testing
@testable import CompileService

@Suite("TrimSize")
struct TrimSizeTests {
    @Test("dimensions match §9.4's four supported trim sizes")
    func dimensionsMatchSpec() {
        // 5.06x7.81in, not a literal 5.00x8.00in — measured off a real KDP interior
        // PDF's own `/MediaBox` (§ TrimSize's own doc comment), the exact target this
        // trim reproduces.
        #expect(TrimSize.fiveByEight.widthInches == 5.06)
        #expect(TrimSize.fiveByEight.heightInches == 7.81)
        #expect(TrimSize.fiveQuarterByEight.widthInches == 5.25)
        #expect(TrimSize.fiveQuarterByEight.heightInches == 8)
        #expect(TrimSize.fiveHalfByEightHalf.widthInches == 5.5)
        #expect(TrimSize.fiveHalfByEightHalf.heightInches == 8.5)
        #expect(TrimSize.sixByNine.widthInches == 6)
        #expect(TrimSize.sixByNine.heightInches == 9)
    }
}

@Suite("GutterCalculator")
struct GutterCalculatorTests {
    // These are the *extra* margin on top of the fixed 0.5in outside margin, not a
    // total inside margin by themselves (§ GutterCalculator's own doc comment) — the
    // base tier is set so a 125-page book (the real KDP reference `TrimSize
    // .fiveByEight` reproduces) lands on that reference's exact measured 0.75in
    // total inside margin (0.5 + 0.25).
    @Test("uses 0.25in at and under 150 pages")
    func shortBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 1) == 0.25)
        #expect(GutterCalculator.gutterInches(forPageCount: 150) == 0.25)
    }

    @Test("uses 0.375in from 151 to 300 pages")
    func mediumBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 151) == 0.375)
        #expect(GutterCalculator.gutterInches(forPageCount: 300) == 0.375)
    }

    @Test("uses 0.5in from 301 to 500 pages")
    func longBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 301) == 0.5)
        #expect(GutterCalculator.gutterInches(forPageCount: 500) == 0.5)
    }

    @Test("uses 0.625in past 500 pages")
    func veryLongBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 501) == 0.625)
        #expect(GutterCalculator.gutterInches(forPageCount: 700) == 0.625)
        #expect(GutterCalculator.gutterInches(forPageCount: 2000) == 0.625)
    }
}
