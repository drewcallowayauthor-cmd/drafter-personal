import Foundation

/// §4.3: numeric filename prefixes are the sole source of truth for ordering.
/// `01 `, `02 `, `03 ` … zero-padded to two digits (three past 99 items).
public enum FilenamePrefix {
    public struct Parsed: Equatable {
        public let prefix: Int?
        public let displayName: String
    }

    /// Splits `"02 The Board.md"` into prefix `2` and display name `"The Board"`.
    /// A missing or malformed prefix yields `prefix: nil` so callers can sort it
    /// after prefixed siblings, alphabetically, per §4.3's tolerance rule.
    public static func parse(_ filename: String) -> Parsed {
        let stem = (filename as NSString).deletingPathExtension
        guard let spaceIndex = stem.firstIndex(of: " ") else {
            return Parsed(prefix: nil, displayName: stem)
        }
        let prefixSubstring = stem[stem.startIndex..<spaceIndex]
        guard !prefixSubstring.isEmpty, prefixSubstring.allSatisfy(\.isNumber), let prefix = Int(prefixSubstring) else {
            return Parsed(prefix: nil, displayName: stem)
        }
        let name = stem[stem.index(after: spaceIndex)...]
        return Parsed(prefix: prefix, displayName: String(name))
    }

    /// Sorts by prefix, falling back to alphabetical by display name when the prefix
    /// is missing or tied.
    public static func sort(_ filenames: [String]) -> [String] {
        filenames.sorted { lhs, rhs in
            let parsedLHS = parse(lhs)
            let parsedRHS = parse(rhs)
            switch (parsedLHS.prefix, parsedRHS.prefix) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return parsedLHS.displayName.localizedStandardCompare(parsedRHS.displayName) == .orderedAscending
            }
        }
    }

    /// Renumbers a set of items so prefixes stay dense (`01, 02, 03`, never `01, 03, 07`),
    /// preserving the caller's order. `digits` matches §4.3's "3 if a chapter exceeds
    /// 99 scenes" rule.
    public static func resequence(displayNames: [String], digits: Int = 2) -> [String] {
        displayNames.enumerated().map { index, name in
            let number = String(index + 1)
            let padded = String(repeating: "0", count: max(0, digits - number.count)) + number
            return "\(padded) \(name)"
        }
    }
}
