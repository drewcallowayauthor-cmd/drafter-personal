import DrafterCore
import Foundation

/// Outcome of `GitService.merge(with:in:)` — distinct from a thrown error because a
/// conflicted merge (§5.7) is an expected, handled state, not a failure.
public enum MergeResult: Sendable, Equatable {
    case clean
    case conflicted(paths: [String])
}

/// Subprocess wrapper around `git` (§7, §Appendix A). Callers get one serial actor per
/// project — never concurrent git in the same working tree.
public actor GitService {
    private let processRunner: ProcessRunning
    private let gitExecutableURL: URL
    /// The GitHub PAT (§5.3), if any — threaded into every subprocess invocation as a
    /// `-c http.extraHeader` flag (see `authArguments()`) rather than ever being
    /// written into `.git/config` or a remote URL, matching §5.3's "never store a
    /// token... in `.git/config`". `nil` for a local-only project, or one relying on
    /// pre-existing credentials (SSH keys, an existing credential helper — §5.3 path 1).
    private let authToken: String?

    public init(
        processRunner: ProcessRunning,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        authToken: String? = nil
    ) {
        self.processRunner = processRunner
        self.gitExecutableURL = gitExecutableURL
        self.authToken = authToken
    }

    /// `-c http.extraHeader="Authorization: Basic <base64(x-access-token:token)>"` —
    /// git's smart-HTTP backend (and GitHub's implementation of it) only recognizes
    /// Basic auth, not a bearer token; the REST API (`GitHubAPIClient`) is the only
    /// place a raw `Bearer` header applies. The username is conventionally
    /// `x-access-token` (what GitHub Actions' own checkout uses) — GitHub only checks
    /// the password (the PAT) for token auth, so any non-empty username works. Passed
    /// per-invocation rather than ever being written into `.git/config` (§5.3).
    private func authArguments() -> [String] {
        guard let authToken, !authToken.isEmpty else { return [] }
        let credentials = Data("x-access-token:\(authToken)".utf8).base64EncodedString()
        return ["-c", "http.extraHeader=Authorization: Basic \(credentials)"]
    }

    /// `git rev-parse --verify --quiet <ref>` — whether `ref` resolves to a commit,
    /// without throwing on failure. A missing ref is an expected outcome here (e.g. a
    /// freshly-created GitHub repo has no branches at all until the first push
    /// succeeds — §5.2), not a genuine error, so callers branch on the `Bool` rather
    /// than catching.
    public func refExists(_ ref: String, in workingTree: URL) async throws -> Bool {
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: authArguments() + ["rev-parse", "--verify", "--quiet", ref],
            currentDirectoryURL: workingTree,
            environment: ["GIT_TERMINAL_PROMPT": "0"]
        )
        return result.succeeded
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

    /// `git count-objects -vH` — human-readable object-store size for the Versioning
    /// pane's "history size" display (§12). Returns the raw command output rather than
    /// parsing it: the format is stable but not documented as an API, and the pane just
    /// needs something legible to show the writer, not a value to compute against.
    public func repositorySize(workingTree: URL) async throws -> String {
        let result = try await run(["count-objects", "-vH"], in: workingTree)
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `git gc` — the Versioning pane's "Run Maintenance" action for Git-mode projects
    /// (§12), mirroring Local-file mode's `SnapshotCoordinator.pruneSnapshots()`.
    public func runMaintenance(workingTree: URL) async throws {
        _ = try await run(["gc"], in: workingTree)
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
    /// `ref` scopes the log to a specific branch/remote-ref (e.g. `origin/main` for
    /// §6.4's concurrent-editing check) instead of the default `HEAD`.
    public func log(for path: String? = nil, ref: String? = nil, in workingTree: URL) async throws -> [CommitLogEntry] {
        var arguments = ["log"]
        if let ref {
            arguments.append(ref)
        }
        if path != nil {
            arguments.append("--follow")
        }
        arguments.append("--format=%H%x1f%at%x1f%s%x1f%an%x1f%(trailers:key=Machine,valueonly=true,separator=)")
        if let path {
            arguments += ["--", path]
        }

        let result = try await run(arguments, in: workingTree)
        return Self.parseLogEntries(result.standardOutput)
    }

    /// The most recent commit touching `path` reachable from `ref` — used by §5.7's
    /// conflict sheet to label each side ("Mine — edited 14 minutes ago on
    /// Josiah-Mac-Studio"): `ref` is `HEAD` for "mine" and `MERGE_HEAD` for "theirs"
    /// during an unresolved merge. `nil` if `path` has no history reachable from `ref`.
    public func lastCommit(for path: String, at ref: String, in workingTree: URL) async throws -> CommitLogEntry? {
        let arguments = [
            "log", "-1",
            "--format=%H%x1f%at%x1f%s%x1f%an%x1f%(trailers:key=Machine,valueonly=true,separator=)",
            ref, "--", path
        ]
        let result = try await run(arguments, in: workingTree)
        return Self.parseLogEntries(result.standardOutput).first
    }

    private static func parseLogEntries(_ output: String) -> [CommitLogEntry] {
        output
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

    /// `git clone <url> <destination>` (§5.9) — `destination`'s parent directory must
    /// already exist; git creates `destination` itself and refuses to run if it does.
    public func clone(url: String, to destination: URL) async throws {
        let parent = destination.deletingLastPathComponent()
        _ = try await run(["clone", url, destination.path], in: parent)
    }

    /// `git remote add <name> <url>` (Appendix A, §5.2 step 3).
    public func addRemote(url: String, name: String = "origin", in workingTree: URL) async throws {
        _ = try await run(["remote", "add", name, url], in: workingTree)
    }

    /// `git remote get-url <name>` — `nil` when no such remote is configured, rather
    /// than throwing, since "not connected to GitHub yet" is an expected, common state
    /// (§5.2's local-only project) that callers branch on rather than catch.
    public func remoteURL(named name: String = "origin", in workingTree: URL) async throws -> String? {
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: ["remote", "get-url", name],
            currentDirectoryURL: workingTree,
            environment: ["GIT_TERMINAL_PROMPT": "0"]
        )
        guard result.succeeded else { return nil }
        let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `git push -u <remote> <branch>` — the first push of a newly connected repo
    /// (§5.2 step 3), distinct from the ongoing `push(remote:branch:in:)` because only
    /// the first push needs to set the upstream tracking branch.
    public func pushSettingUpstream(remote: String = "origin", branch: String = "main", in workingTree: URL) async throws {
        _ = try await run(["push", "-u", remote, branch], in: workingTree)
    }

    /// `git merge <ref>` — the "diverged" case in §5.6. A conflicted merge is not treated
    /// as a thrown error: git's non-zero exit for conflicts is expected and handled by
    /// checking for conflicted files, distinct from a genuine failure (§5.7's territory,
    /// not an exceptional one).
    public func merge(with ref: String, message: String? = nil, in workingTree: URL) async throws -> MergeResult {
        var arguments = ["merge", ref]
        if let message {
            arguments += ["-m", message]
        }
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: arguments,
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

    /// `git show :3:<path>` — the "theirs" side of an unresolved conflict (merge stage
    /// 3), used by "Keep Both" (§5.7) to write their version out as a second file
    /// without discarding it.
    public func theirsContent(path: String, in workingTree: URL) async throws -> String {
        let result = try await run(["show", ":3:\(path)"], in: workingTree)
        return result.standardOutput
    }

    /// `git mv <old> <new>` (§4.3) — renames used for reordering, so history follows
    /// the file.
    public func move(from oldPath: String, to newPath: String, in workingTree: URL) async throws {
        _ = try await run(["mv", oldPath, newPath], in: workingTree)
    }

    private func run(_ arguments: [String], in workingTree: URL) async throws -> ProcessResult {
        let result = try await processRunner.run(
            executableURL: gitExecutableURL,
            arguments: authArguments() + arguments,
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

/// §9.1's `VersioningSource` conformance — lets `HistoryViewModel` drive either Git
/// mode or Local-file mode through the same interface. `log(for:ref:in:)`'s `ref`
/// parameter has no equivalent here, so this always scopes to `HEAD`.
extension GitService: VersioningSource {
    public func log(for path: String?, in workingTree: URL) async throws -> [CommitLogEntry] {
        try await log(for: path, ref: nil, in: workingTree)
    }
}
