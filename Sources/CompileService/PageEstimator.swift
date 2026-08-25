import Foundation

/// §9.6's compile-sheet "live estimate" — word count plus, for targets where a page
/// count means something, a rough page estimate shown before compiling. These are
/// approximations for the UI, not the authoritative count: `PrintExportCoordinator`
/// determines Print PDF's real page count via an actual two-pass typst compile (§9.4,
/// `GutterCalculator`), and a DOCX/SMF page count is inherently reader-dependent
/// (varies with the reader's own Word settings) — the 250-words-per-page figure below
/// is the industry-standard "manuscript page" convention literary agents and editors
/// use when they ask how long a submission is, not a claim about actual pagination.
public enum PageEstimator {
    public static func manuscriptPages(wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        return Int((Double(wordCount) / 250).rounded(.up))
    }

    /// A rough print-page estimate from trim size/font/leading: usable text area
    /// divided by an approximate per-word footprint. Margins mirror
    /// `TypstDocumentGenerator`'s real ones exactly (0.5in outside, 0.75in top, 0.8in
    /// bottom, inside = outside + gutter — read directly out of the reference
    /// project's own Scrivener compile-format XML, not eyeballed) rather than a flat
    /// guess — the gutter alone
    /// grows to 0.75in for a long book (`GutterCalculator`), and a flat "~0.7in
    /// inside/outside" assumption was quietly eating a quarter-inch of real usable
    /// width right when it mattered most. Iterates the same way
    /// `PrintExportCoordinator` does: gutter depends on the page count, which depends
    /// on the gutter, so estimate once, then redo it with the gutter that page count
    /// actually implies.
    ///
    /// The average-character-width constant (0.68× point size) is calibrated against
    /// a real compiled PDF's measured word density (~160 words/page at 10.5pt
    /// Palatino on a 5x8 trim with a 0.75in gutter) — not assumed. An earlier 0.5×
    /// guess, checked only against a degenerate test corpus of one repeated short
    /// word, was far too narrow for real prose's mix of word lengths and undercounted
    /// real output by close to half.
    public static func printPages(wordCount: Int, trimSize: TrimSize, pointSize: Double, leading: Double) -> Int {
        guard wordCount > 0, pointSize > 0, leading > 0 else { return 0 }

        var gutterInches = GutterCalculator.gutterInches(forPageCount: 1)
        var pages = 0
        for _ in 0..<2 {
            pages = estimatedPages(
                wordCount: wordCount, trimSize: trimSize, pointSize: pointSize, leading: leading,
                gutterInches: gutterInches
            )
            let neededGutter = GutterCalculator.gutterInches(forPageCount: pages)
            if neededGutter == gutterInches { break }
            gutterInches = neededGutter
        }
        return pages
    }

    private static func estimatedPages(
        wordCount: Int, trimSize: TrimSize, pointSize: Double, leading: Double, gutterInches: Double
    ) -> Int {
        let outsideMargin = 0.5
        let topMargin = 0.75
        let bottomMargin = 0.8
        let insideMargin = outsideMargin + gutterInches

        let usableHeightPoints = max(1, (trimSize.heightInches - topMargin - bottomMargin) * 72)
        let usableWidthPoints = max(1, (trimSize.widthInches - insideMargin - outsideMargin) * 72)
        let lineHeightPoints = pointSize * leading
        let linesPerPage = usableHeightPoints / lineHeightPoints
        let avgCharWidthPoints = pointSize * 0.68
        let charsPerLine = usableWidthPoints / avgCharWidthPoints
        let wordsPerLine = charsPerLine / 6
        let wordsPerPage = max(1, wordsPerLine * linesPerPage)
        return max(1, Int((Double(wordCount) / wordsPerPage).rounded(.up)))
    }
}
