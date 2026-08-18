import Testing
@testable import CompileService

@Suite("TrimSize")
struct TrimSizeTests {
    @Test("dimensions match §9.4's four supported trim sizes")
    func dimensionsMatchSpec() {
        #expect(TrimSize.fiveByEight.widthInches == 5)
        #expect(TrimSize.fiveByEight.heightInches == 8)
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
    @Test("uses 0.375in at and under 150 pages")
    func shortBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 1) == 0.375)
        #expect(GutterCalculator.gutterInches(forPageCount: 150) == 0.375)
    }

    @Test("uses 0.5in from 151 to 300 pages")
    func mediumBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 151) == 0.5)
        #expect(GutterCalculator.gutterInches(forPageCount: 300) == 0.5)
    }

    @Test("uses 0.625in from 301 to 500 pages")
    func longBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 301) == 0.625)
        #expect(GutterCalculator.gutterInches(forPageCount: 500) == 0.625)
    }

    @Test("uses 0.75in past 500 pages")
    func veryLongBook() {
        #expect(GutterCalculator.gutterInches(forPageCount: 501) == 0.75)
        #expect(GutterCalculator.gutterInches(forPageCount: 700) == 0.75)
        #expect(GutterCalculator.gutterInches(forPageCount: 2000) == 0.75)
    }
}
