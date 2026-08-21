import Foundation

/// §12.2 point 7's guard: without this, opening the same project in two windows
/// would attach two independent `FileSystemWatcher`s, `AutocommitScheduler`s, and
/// `SyncScheduler`s to one working tree — racing independent commits into the same
/// repo. A process-wide actor rather than per-window state, since the whole point
/// is visibility across windows (each `ContentView` owns its own `ProjectViewModel`).
///
/// This only guards windows within this process — it doesn't reach across two
/// separately-launched processes (e.g. two `swift run` invocations in development).
/// A real packaged `.app` launch doesn't have that gap: macOS routes a second
/// double-click of the same bundle to the existing process's `WindowGroup` rather
/// than starting a new one.
actor OpenProjectRegistry {
    static let shared = OpenProjectRegistry()

    private var openRoots: Set<String> = []

    private init() {}

    /// Registers `root` as open and returns `true`, or returns `false` without
    /// registering if another window already has it open.
    func tryRegister(_ root: URL) -> Bool {
        let key = Self.key(for: root)
        guard !openRoots.contains(key) else { return false }
        openRoots.insert(key)
        return true
    }

    func unregister(_ root: URL) {
        openRoots.remove(Self.key(for: root))
    }

    /// Resolved and standardized so a symlinked path and its real path collide as
    /// the same project, matching `SyncedFolderGuard`'s own resolution rule.
    private static func key(for root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
