import DrafterCore
import Foundation

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
