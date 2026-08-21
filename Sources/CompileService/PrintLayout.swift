import Foundation

/// The four trim sizes §9.4 supports, in inches. `fiveByEight`'s exact dimensions
/// are 5.06x7.81in, not a literal 5.00x8.00in — measured directly off a real KDP
/// interior PDF's own `/MediaBox` (a Scrivener "5x8" KDP export that uploaded and
/// bound correctly as a 5x8 book), not assumed or rounded. That reference is the
/// exact target this trim reproduces.
public enum TrimSize: String, CaseIterable, Sendable {
    case fiveByEight = "5x8"
    case fiveQuarterByEight = "5.25x8"
    case fiveHalfByEightHalf = "5.5x8.5"
    case sixByNine = "6x9"

    public var widthInches: Double {
        switch self {
        case .fiveByEight: return 5.06
        case .fiveQuarterByEight: return 5.25
        case .fiveHalfByEightHalf: return 5.5
        case .sixByNine: return 6
        }
    }

    public var heightInches: Double {
        switch self {
        case .fiveByEight: return 7.81
        case .fiveQuarterByEight: return 8
        case .fiveHalfByEightHalf: return 8.5
        case .sixByNine: return 9
        }
    }
}

/// §9.4's gutter-by-page-count table. Gutter depends on final page count, which
/// depends on layout, so the export pipeline compiles once, reads the resulting page
/// count, and recompiles with the correct gutter if it crosses a threshold — this is
/// the pure lookup half of that two-pass process.
///
/// This is `TypstDocumentGenerator`'s *extra* margin on top of the fixed 0.5in
/// outside margin (`insideMargin = outsideMargin + gutterInches`), not the total
/// inside margin by itself. The base (<=150 page) tier is set so a book the size of
/// the same real KDP reference `TrimSize.fiveByEight` reproduces (125 pages) lands on
/// its exact measured inside margin: 0.5 (outside) + 0.25 (gutter) = 0.75in, matching
/// that reference's own `/MediaBox`-derived text-column position precisely rather
/// than approximately. The other tiers keep the same 0.125in step this table has
/// always used.
public enum GutterCalculator {
    public static func gutterInches(forPageCount pageCount: Int) -> Double {
        switch pageCount {
        case ...150: return 0.25
        case 151...300: return 0.375
        case 301...500: return 0.5
        default: return 0.625
        }
    }
}
