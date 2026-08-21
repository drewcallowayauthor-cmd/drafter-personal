import Foundation

/// One row of version history — a git commit (§6.8) or a Local-file snapshot (§7.4).
/// Deliberately shaped after `git log`'s output (Appendix A) rather than after
/// `History/`, since a snapshot's "subject" is built by the same `CommitMessageBuilder`
/// used for commit messages (§7.2: "uses the same trigger table"), so both mechanisms
/// produce the exact same row shape and the History UI (§9.1) never needs to know which
/// one it's looking at.
public struct CommitLogEntry: Sendable, Equatable, Identifiable {
    public var id: String { sha }
    /// A commit sha (Git mode) or a `History/` snapshot folder name (Local-file mode).
    public let sha: String
    public let date: Date
    public let subject: String
    public let authorName: String
    /// The `Machine:` trailer (§6.4) — empty for commits that predate this convention
    /// or were made outside the app.
    public let machineName: String

    public init(sha: String, date: Date, subject: String, authorName: String, machineName: String) {
        self.sha = sha
        self.date = date
        self.subject = subject
        self.authorName = authorName
        self.machineName = machineName
    }
}

/// The shape `HistoryViewModel` (§9.1's shared History UI) needs from either mode's
/// backing store: a log of entries touching one file (or the whole project, when `path`
/// is `nil`), and that file's contents at a given entry. `GitService` and
/// `SnapshotService` are its two conformances — see §6.8/§7.4.
public protocol VersioningSource: Sendable {
    func log(for path: String?, in workingTree: URL) async throws -> [CommitLogEntry]
    func show(path: String, at id: String, in workingTree: URL) async throws -> String
}
