import Foundation
import Observation
import ProjectStore

/// Drives `ProjectFindReplaceSheet` (§8.3 point 8, ⇧⌘F). Owns the query/options and the
/// debounced re-search, but not the project itself — `performSearch`/`performReplace` are
/// closures into `ProjectViewModel` so this stays testable without a real `Project`.
@MainActor
@Observable
final class ProjectFindReplaceViewModel {
    var query: String = "" {
        didSet { if query != oldValue { scheduleSearch(debounced: true) } }
    }
    var replacement: String = ""
    var caseSensitive: Bool = false {
        didSet { if caseSensitive != oldValue { scheduleSearch(debounced: false) } }
    }
    var matchWholeWord: Bool = false {
        didSet { if matchWholeWord != oldValue { scheduleSearch(debounced: false) } }
    }
    private(set) var matches: [ProjectSearchMatch] = []
    private(set) var isSearching = false
    private(set) var isReplacing = false

    private let performSearch: (ProjectSearchOptions) async -> [ProjectSearchMatch]
    /// Returns the scene URLs actually rewritten on disk.
    private let performReplace: ([ProjectSearchMatch], String) async -> Set<URL>
    /// Flushes the editor's pending autosave, if any, before a replace touches disk —
    /// otherwise a dirty open scene's next autosave would silently undo the replacement.
    private let flushOpenScene: () -> Void
    /// Reloads the editor's open scene from disk if it's one of the just-rewritten URLs,
    /// so an in-progress edit of the same scene doesn't keep showing pre-replace text.
    private let reloadIfOpen: (Set<URL>) -> Void

    private var searchTask: Task<Void, Never>?

    init(
        performSearch: @escaping (ProjectSearchOptions) async -> [ProjectSearchMatch],
        performReplace: @escaping ([ProjectSearchMatch], String) async -> Set<URL>,
        flushOpenScene: @escaping () -> Void,
        reloadIfOpen: @escaping (Set<URL>) -> Void
    ) {
        self.performSearch = performSearch
        self.performReplace = performReplace
        self.flushOpenScene = flushOpenScene
        self.reloadIfOpen = reloadIfOpen
    }

    private var currentOptions: ProjectSearchOptions {
        ProjectSearchOptions(query: query, caseSensitive: caseSensitive, matchWholeWord: matchWholeWord)
    }

    private func scheduleSearch(debounced: Bool) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            matches = []
            isSearching = false
            return
        }
        let options = currentOptions
        isSearching = true
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            let results = await performSearch(options)
            guard !Task.isCancelled else { return }
            matches = results
            isSearching = false
        }
    }

    /// Replaces one match, then re-runs the search rather than hand-adjusting every
    /// later match's offset in the same file — simpler, and correct even if the
    /// replacement text itself still matches the query (e.g. a case-insensitive search).
    func replace(_ match: ProjectSearchMatch) async {
        await performReplace(matches: [match])
    }

    func replaceAll() async {
        await performReplace(matches: matches)
    }

    private func performReplace(matches: [ProjectSearchMatch]) async {
        guard !matches.isEmpty else { return }
        isReplacing = true
        flushOpenScene()
        let rewrittenURLs = await performReplace(matches, replacement)
        reloadIfOpen(rewrittenURLs)
        scheduleSearch(debounced: false)
        isReplacing = false
    }
}
