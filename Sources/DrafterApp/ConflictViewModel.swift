import DrafterCore
import Foundation
import GitService
import Observation

/// Backs the §5.7 conflict sheet: one `FileConflict` per path in `.conflicted`'s file
/// list, resolved individually, then finalized (commit + push) once every path is done.
@MainActor
@Observable
final class ConflictViewModel {
    struct FileConflict: Identifiable, Equatable {
        let path: String
        var id: String { path }
        var mine: CommitLogEntry?
        var theirs: CommitLogEntry?
        var isResolved = false
    }

    private(set) var conflicts: [FileConflict]
    private(set) var errorMessage: String?
    private(set) var isFinalizing = false

    private let gitService: GitService
    private let conflictResolver: ConflictResolver
    private let workingTree: URL
    private let machineName: String

    init(
        paths: [String],
        gitService: GitService,
        workingTree: URL,
        machineName: String,
        atomicFileWriter: AtomicFileWriting = LiveAtomicFileWriter()
    ) {
        self.conflicts = paths.map { FileConflict(path: $0) }
        self.gitService = gitService
        self.conflictResolver = ConflictResolver(gitService: gitService, atomicFileWriter: atomicFileWriter, workingTree: workingTree)
        self.workingTree = workingTree
        self.machineName = machineName
    }

    var allResolved: Bool {
        !conflicts.isEmpty && conflicts.allSatisfy(\.isResolved)
    }

    /// Loads each side's last-touched commit (§5.7's "Mine — edited 14 minutes ago on
    /// Josiah-Mac-Studio" labels) — best-effort, since a missing label shouldn't block
    /// resolving the conflict itself.
    func loadMetadata() async {
        for index in conflicts.indices {
            let path = conflicts[index].path
            conflicts[index].mine = try? await gitService.lastCommit(for: path, at: "HEAD", in: workingTree)
            conflicts[index].theirs = try? await gitService.lastCommit(for: path, at: "MERGE_HEAD", in: workingTree)
        }
    }

    func diffLines(for conflict: FileConflict) async -> [SceneDiffLine] {
        let mine = (try? await gitService.show(path: conflict.path, at: "HEAD", in: workingTree)) ?? ""
        let theirs = (try? await gitService.theirsContent(path: conflict.path, in: workingTree)) ?? ""
        return SceneDiff.diff(old: mine, new: theirs)
    }

    func keepMine(_ conflict: FileConflict) async {
        do {
            try await conflictResolver.keepMine(path: conflict.path)
            markResolved(conflict.path)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func keepTheirs(_ conflict: FileConflict) async {
        do {
            try await conflictResolver.keepTheirs(path: conflict.path)
            markResolved(conflict.path)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// §5.7's safe default: mine stays in place, theirs is written alongside it as
    /// `<name> (from <machine> <date>).<ext>`.
    func keepBoth(_ conflict: FileConflict) async {
        do {
            try await conflictResolver.keepBoth(path: conflict.path, duplicatePath: Self.duplicatePath(for: conflict))
            markResolved(conflict.path)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Once every path is resolved: commit and push. Returns whether it succeeded so
    /// the sheet knows whether it's safe to dismiss.
    func finalize() async -> Bool {
        guard allResolved else { return false }
        isFinalizing = true
        defer { isFinalizing = false }
        do {
            try await conflictResolver.finalize(machineName: machineName)
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }

    private func markResolved(_ path: String) {
        guard let index = conflicts.firstIndex(where: { $0.path == path }) else { return }
        conflicts[index].isResolved = true
    }

    private static func duplicatePath(for conflict: FileConflict) -> String {
        let url = URL(fileURLWithPath: conflict.path)
        let directory = url.deletingLastPathComponent().path
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        let machine = conflict.theirs?.machineName.isEmpty == false ? conflict.theirs!.machineName : "another machine"
        let date = conflict.theirs.map(Self.shortDate) ?? Self.shortDate(Date())

        let newName = ext.isEmpty ? "\(base) (from \(machine) \(date))" : "\(base) (from \(machine) \(date)).\(ext)"
        return directory.isEmpty || directory == "." ? newName : "\(directory)/\(newName)"
    }

    private static func shortDate(_ entry: CommitLogEntry) -> String {
        shortDate(entry.date)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
