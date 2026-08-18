import DrafterCore
import Foundation

/// Outcome of `GitService.merge(with:in:)` — distinct from a thrown error because a
/// conflicted merge (§5.7) is an expected, handled state, not a failure.
public enum MergeResult: Sendable, Equatable {
    case clean
    case conflicted(paths: [String])
}

/// One row of `git log` output (§5.8's History panel, Appendix A's log format).
public struct CommitLogEntry: Sendable, Equatable {
    public let sha: String
    public let date: Date
    public let subject: String
    public let authorName: String
    /// The `Machine:` trailer (§5.4) — empty for commits that predate this convention
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

/// Subprocess wrapper around `git` (§7, §Appendix A). Callers get one serial actor per
/// project — never concurrent git in the same working tree.
public actor GitService {
    private let processRunner: ProcessRunning
    private let gitExecutableURL: URL

    public init(processRunner: ProcessRunning, gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.processRunner = processRunner
        self.gitExecutableURL = gitExecutableURL
    }

    /// `git status --porcelain` — empty output means nothing to commit (§5.4).
    public func hasUncommittedChanges(in workingTree: URL) async throws -> Bool {
        let result = try await run(["status", "--porcelain"], in: workingTree)
        return !result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `git rev-list --left-right --count HEAD...origin/main` — used to classify the
    /// relationship to the remote before deciding fast-forward vs merge (§5.6).
    public func divergence(from ref: String, in workingTree: URL) async throws -> (ahead: Int, behind: Int) {
        let result = try await run(["rev-list", "--left-right", "--count", "HEAD...\(ref)"], in: workingTree)
        let parts = result.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t")
            .compactMap { Int($0) }
        guard parts.count == 2 else {
            throw DrafterError.processFailed(
                command: "git rev-list",
                exitCode: result.exitCode,
                stderr: "unexpected output: \(result.standardOutput)"
            )
        }
        return (ahead: parts[0], behind: parts[1])
    }

    /// `git init -b main` (Appendix A) — the working tree must already exist on disk;
    /// this just makes it a git repo.
    public func initRepository(in workingTree: URL) async throws {
        _ = try await run(["init", "-b", "main"], in: workingTree)
    }

    /// `git config user.name` / `user.email` (Appendix A), scoped locally to this repo
    /// — never touches the user's global git config.
    public func configureIdentity(name: String, email: String, in workingTree: URL) async throws {
        _ = try await run(["config", "user.name", name], in: workingTree)
        _ = try await run(["config", "user.email", email], in: workingTree)
    }

    /// Extends Appendix A's `--format=%H%x1f%at%x1f%s%x1f%an` with a 5th field pulling
    /// just the `Machine:` trailer's value (§5.4), which §5.8's History panel needs to
    /// distinguish "you, 5 minutes ago on this machine" from "you, on the other one."
    /// `--follow` when `path` is given — history for one file, renames followed.
    /// Without a path, drops `--follow` (meaningless repo-wide) for the project-wide
    /// Timeline view (§5.8).
    public func log(for path: String? = nil, in workingTree: URL) async throws -> [CommitLogEntry] {
        var arguments = ["log"]
        if path != nil {
            arguments.append("--follow")
        }
        arguments.append("--format=%H%x1f%at%x1f%s%x1f%an%x1f%(trailers:key=Machine,valueonly=true,separator=)")
        if let path {
            arguments += ["--", path]
        }

        let result = try await run(arguments, in: workingTree)
        return result.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> CommitLogEntry? in
                let fields = line.components(separatedBy: "\u{1F}")
                guard fields.count == 5, let timestamp = TimeInterval(fields[1]) else { return nil }
                return CommitLogEntry(
                    sha: fields[0],
                    date: Date(timeIntervalSince1970: timestamp),
                    subject: fields[2],
                    authorName: fields[3],
                    machineName: fields[4]
                )
            }
    }

    /// `git show <sha>:"<path>"` (Appendix A) — a file's contents at a given commit,
    /// used to restore an older version (§5.8).
    public func show(path: String, at sha: String, in workingTree: URL) async throws -> String {
        let result = try await run(["show", "\(sha):\(path)"], in: workingTree)
        return result.standardOutput
    }

    /// `git add -A` (§5.4) — stage everything ahead of a commit.
    public func stageAll(in workingTree: URL) async throws {
        _ = try await run(["add", "-A"], in: workingTree)
    }

    /// `git commit -m <message>`. Callers must check `hasUncommittedChanges` first —
    /// §5.4 forbids empty commits, and this doesn't re-check on their behalf.
    public func commit(message: String, in workingTree: URL) async throws {
        _ = try await run(["commit", "-m", message], in: workingTree)
    }

    /// `git fetch <remote>`.
    public func fetch(remote: String = "origin", in workingTree: URL) async throws {
        _ = try await run(["fetch", remote], in: workingTree)
    }

    /// `git merge --ff-only <ref>` — the "local behind" case in §5.6.
    public func fastForwardMerge(to ref: String, in workingTree: URL) async throws {
        _ = try await run(["merge", "--ff-only", ref], in: workingTree)
    }

    /// `git push <remote> <branch>`.
    public func push(remote: String = "origin", branch: String = "main", in workingTree: URL) async throws {
        _ = try await run(["push", remote, branch], in: workingTree)
    }

    /// `git merge <ref>` — the "diverged" case in §5.6. A conflicted merge is not treated
    /// as a thrown error: git's non-zero exit for conflicts is expected and handled by
    /// checking for conflicted files, distinct from a genuine failure (§5.7's territory,
    /// not an exceptional one).
    public func merge(with ref: String, in workingTree: URL) async throws -> MergeResult {
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: ["merge", ref],
            currentDirectoryURL: workingTree,
            environment: ["GIT_TERMINAL_PROMPT": "0"]
        )
        if result.succeeded { return .clean }

        let conflicts = try await conflictedFiles(in: workingTree)
        guard !conflicts.isEmpty else {
            throw DrafterError.processFailed(
                command: "git merge \(ref)",
                exitCode: result.exitCode,
                stderr: result.standardError
            )
        }
        return .conflicted(paths: conflicts)
    }

    /// `git diff --name-only --diff-filter=U` (Appendix A) — files with unresolved
    /// conflict markers.
    public func conflictedFiles(in workingTree: URL) async throws -> [String] {
        let result = try await run(["diff", "--name-only", "--diff-filter=U"], in: workingTree)
        return result.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// `git checkout --ours <path>` — the "Keep Mine" resolution (§5.7).
    public func keepOurs(path: String, in workingTree: URL) async throws {
        _ = try await run(["checkout", "--ours", path], in: workingTree)
    }

    /// `git checkout --theirs <path>` — the "Keep Theirs" resolution (§5.7).
    public func keepTheirs(path: String, in workingTree: URL) async throws {
        _ = try await run(["checkout", "--theirs", path], in: workingTree)
    }

    /// `git mv <old> <new>` (§4.3) — renames used for reordering, so history follows
    /// the file.
    public func move(from oldPath: String, to newPath: String, in workingTree: URL) async throws {
        _ = try await run(["mv", oldPath, newPath], in: workingTree)
    }

    private func run(_ arguments: [String], in workingTree: URL) async throws -> ProcessResult {
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: arguments,
            currentDirectoryURL: workingTree,
            environment: ["GIT_TERMINAL_PROMPT": "0"]
        )
        guard result.succeeded else {
            throw DrafterError.processFailed(
                command: "git \(arguments.joined(separator: " "))",
                exitCode: result.exitCode,
                stderr: result.standardError
            )
        }
        return result
    }
}
