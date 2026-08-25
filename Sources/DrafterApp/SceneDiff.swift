import Foundation

/// A single LCS-based diff operation over a sequence of elements. Shared by both the
/// line-level and word-level passes in `SceneDiff`.
public enum DiffOp<Element: Equatable>: Equatable {
    case equal(Element)
    case delete(Element)
    case insert(Element)
}

/// Plain LCS diff via the standard O(n·m) dynamic-programming table. Fine at both scales
/// this gets used at: line-level over a whole scene (paragraph count is small, §4.7) and
/// word-level within a single changed paragraph (bounded by one paragraph's length) —
/// never over the whole scene's word count at once.
enum DiffAlgorithm {
    static func diff<Element: Equatable>(_ old: [Element], _ new: [Element]) -> [DiffOp<Element>] {
        let oldCount = old.count
        let newCount = new.count
        var lengths = Array(repeating: Array(repeating: 0, count: newCount + 1), count: oldCount + 1)
        for oldIdx in stride(from: oldCount - 1, through: 0, by: -1) {
            for newIdx in stride(from: newCount - 1, through: 0, by: -1) {
                lengths[oldIdx][newIdx] = old[oldIdx] == new[newIdx]
                    ? lengths[oldIdx + 1][newIdx + 1] + 1
                    : max(lengths[oldIdx + 1][newIdx], lengths[oldIdx][newIdx + 1])
            }
        }

        var result: [DiffOp<Element>] = []
        var oldIdx = 0
        var newIdx = 0
        while oldIdx < oldCount, newIdx < newCount {
            if old[oldIdx] == new[newIdx] {
                result.append(.equal(old[oldIdx]))
                oldIdx += 1
                newIdx += 1
            } else if lengths[oldIdx + 1][newIdx] >= lengths[oldIdx][newIdx + 1] {
                result.append(.delete(old[oldIdx]))
                oldIdx += 1
            } else {
                result.append(.insert(new[newIdx]))
                newIdx += 1
            }
        }
        while oldIdx < oldCount {
            result.append(.delete(old[oldIdx]))
            oldIdx += 1
        }
        while newIdx < newCount {
            result.append(.insert(new[newIdx]))
            newIdx += 1
        }
        return result
    }
}

/// One row of a two-pane diff (§5.8). `.modified` carries a word-level sub-diff for
/// each side, computed only for the paragraphs that actually changed.
public struct SceneDiffLine: Equatable {
    public enum Kind: Equatable {
        case unchanged
        case added
        case removed
        case modified
    }

    public let kind: Kind
    public let oldText: String?
    public let newText: String?
    public let oldWords: [DiffOp<String>]?
    public let newWords: [DiffOp<String>]?
}

public enum SceneDiff {
    /// Line-level diff, with adjacent delete/insert runs paired positionally into
    /// `.modified` rows and word-diffed — the common "this paragraph was edited" case,
    /// distinct from a paragraph purely added or removed. Unpaired leftovers (an
    /// uneven number of deletes vs. inserts in one run) fall back to plain
    /// `.removed`/`.added`.
    public static func diff(old: String, new: String) -> [SceneDiffLine] {
        // "".components(separatedBy: "\n") is [""] — one empty line, not zero — which
        // would pair a spurious empty line against real content and misclassify a
        // brand-new scene's diff as .modified instead of .added.
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let ops = DiffAlgorithm.diff(oldLines, newLines)

        var results: [SceneDiffLine] = []
        var index = 0
        while index < ops.count {
            switch ops[index] {
            case .equal(let line):
                results.append(
                    SceneDiffLine(kind: .unchanged, oldText: line, newText: line, oldWords: nil, newWords: nil)
                )
                index += 1

            default:
                var deletes: [String] = []
                var inserts: [String] = []
                while index < ops.count, case .delete(let line) = ops[index] {
                    deletes.append(line)
                    index += 1
                }
                while index < ops.count, case .insert(let line) = ops[index] {
                    inserts.append(line)
                    index += 1
                }

                let pairCount = min(deletes.count, inserts.count)
                for pair in 0..<pairCount {
                    let wordOps = DiffAlgorithm.diff(tokenize(deletes[pair]), tokenize(inserts[pair]))
                    results.append(
                        SceneDiffLine(
                            kind: .modified,
                            oldText: deletes[pair],
                            newText: inserts[pair],
                            oldWords: wordOps.filter { if case .insert = $0 { return false } else { return true } },
                            newWords: wordOps.filter { if case .delete = $0 { return false } else { return true } }
                        )
                    )
                }
                for extra in deletes[pairCount...] {
                    results.append(
                        SceneDiffLine(kind: .removed, oldText: extra, newText: nil, oldWords: nil, newWords: nil)
                    )
                }
                for extra in inserts[pairCount...] {
                    results.append(
                        SceneDiffLine(kind: .added, oldText: nil, newText: extra, oldWords: nil, newWords: nil)
                    )
                }
            }
        }
        return results
    }

    /// Splits into words and whitespace runs, preserving every character — this is
    /// diffed, not rendered as markdown, so nothing needs stripping.
    private static func tokenize(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\S+|\\s+") else { return [line] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]) }
        }
    }
}
