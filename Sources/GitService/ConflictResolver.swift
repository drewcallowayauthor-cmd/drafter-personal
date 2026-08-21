import DrafterCore
import Foundation

/// Resolves one conflicted file per §5.7. "Compare" (a diff) reuses the app's existing
/// History diff view and isn't this type's concern; this only covers the three
/// resolution actions plus the commit that closes them out.
public actor ConflictResolver {
    private let gitService: GitService
    private let atomicFileWriter: AtomicFileWriting
    private let workingTree: URL

    public init(gitService: GitService, atomicFileWriter: AtomicFileWriting = LiveAtomicFileWriter(), workingTree: URL) {
        self.gitService = gitService
        self.atomicFileWriter = atomicFileWriter
        self.workingTree = workingTree
    }

    /// "Keep Mine" — discard their side, keep the local version, mark resolved.
    public func keepMine(path: String) async throws {
        try await gitService.keepOurs(path: path, in: workingTree)
        try await gitService.stageAll(in: workingTree)
    }

    /// "Keep Theirs" — discard the local side, take their version, mark resolved.
    public func keepTheirs(path: String) async throws {
        try await gitService.keepTheirs(path: path, in: workingTree)
        try await gitService.stageAll(in: workingTree)
    }

    /// "Keep Both" (§5.7's safe default) — mine stays in place untouched, theirs is
    /// written out alongside it under `duplicatePath`, so nothing is silently lost.
    /// The caller (app layer, which already knows the conflicting commit's machine
    /// name and date via `GitService.log`) supplies the duplicate's filename.
    public func keepBoth(path: String, duplicatePath: String) async throws {
        let theirs = try await gitService.theirsContent(path: path, in: workingTree)
        try await gitService.keepOurs(path: path, in: workingTree)

        guard let data = theirs.data(using: .utf8) else {
            throw DrafterError.filesystem(underlying: "theirs content for \(path) was not valid UTF-8")
        }
        try atomicFileWriter.write(data, to: workingTree.appendingPathComponent(duplicatePath))

        try await gitService.stageAll(in: workingTree)
    }

    /// Once every conflicted file has been resolved: commit and push (§5.7's closing
    /// step). Callers should only invoke this after resolving every path returned by
    /// `.conflicted`'s file list — it doesn't check for remaining conflict markers.
    public func finalize(machineName: String) async throws {
        try await gitService.commit(message: "resolve conflicts from \(machineName)", in: workingTree)
        try await gitService.push(in: workingTree)
    }
}
