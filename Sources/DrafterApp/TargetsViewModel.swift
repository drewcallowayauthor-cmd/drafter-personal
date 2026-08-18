import CompileService
import Foundation
import ProjectStore

/// Backs §8.4's Targets panel: project/chapter word totals plus the session count,
/// which "resets on open" — tracked here rather than derived from git history, since a
/// session includes unsaved/uncommitted words too.
@MainActor
@Observable
final class TargetsViewModel {
    private(set) var totals = WordCountTotals(project: 0, perChapter: [])
    private(set) var sessionWords = 0
    private(set) var errorMessage: String?

    func recalculate(binderTree: BinderTree) {
        do {
            totals = try WordCountAggregator.aggregate(binderTree: binderTree) { url in
                try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func recordSessionActivity(wordDelta: Int) {
        sessionWords += wordDelta
    }

    func resetSession() {
        sessionWords = 0
    }
}
