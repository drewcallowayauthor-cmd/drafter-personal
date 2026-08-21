import Foundation

/// Backs the "No Project Open" welcome screen's Recent list (per the design handoff) —
/// nothing tracked recently-opened projects before the redesign, so this is new rather
/// than a pure restyle. UserDefaults-backed, capped and deduplicated by path, most
/// recent first.
enum RecentProjects {
    private static let key = "DrafterRecentProjects"
    private static let limit = 5

    struct Entry: Identifiable, Equatable {
        let title: String
        let path: String
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
    }

    static func load() -> [Entry] {
        let raw = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
        return raw.compactMap { dict in
            guard let title = dict["title"], let path = dict["path"] else { return nil }
            return Entry(title: title, path: path)
        }
    }

    static func record(title: String, root: URL) {
        var entries = load().filter { $0.path != root.path }
        entries.insert(Entry(title: title, path: root.path), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        let raw = entries.map { ["title": $0.title, "path": $0.path] }
        UserDefaults.standard.set(raw, forKey: key)
    }
}
