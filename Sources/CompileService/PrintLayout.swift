import Foundation

/// The four trim sizes §9.4 supports, in inches.
public enum TrimSize: String, CaseIterable, Sendable {
    case fiveByEight = "5x8"
    case fiveQuarterByEight = "5.25x8"
    case fiveHalfByEightHalf = "5.5x8.5"
    case sixByNine = "6x9"

    public var widthInches: Double {
        switch self {
        case .fiveByEight: return 5
        case .fiveQuarterByEight: return 5.25
        case .fiveHalfByEightHalf: return 5.5
        case .sixByNine: return 6
        }
    }

    public var heightInches: Double {
        switch self {
        case .fiveByEight: return 8
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
public enum GutterCalculator {
    public static func gutterInches(forPageCount pageCount: Int) -> Double {
        switch pageCount {
        case ...150: return 0.375
        case 151...300: return 0.5
        case 301...500: return 0.625
        default: return 0.75
        }
    }
}
