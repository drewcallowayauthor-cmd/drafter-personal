import CredentialStore
import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@Suite("RepositoryCoordinator")
struct RepositoryCoordinatorTests {
    @Test("connectToGitHub creates the repo, adds the remote, sets identity to the account email, and pushes -u")
    func connectToGitHubWiresUpRemoteAndIdentity() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 201, jsonObject: [
            "name": "last-call",
            "full_name": "drew/last-call",
            "clone_url": "https://github.com/drew/last-call.git",
            "html_url": "https://github.com/drew/last-call",
            "private": true
        ])
        await requester.script(statusCode: 200, jsonObject: ["login": "drew", "email": "drew@example.com"])
        let coordinator = RepositoryCoordinator(gitService: GitService(processRunner: runner), workingTree: root)

        let repository = try await coordinator.connectToGitHub(
            repositoryName: "last-call",
            authorName: "Drew Calloway",
            apiClient: GitHubAPIClient(requester: requester),
            token: "ghp_abc"
        )

        #expect(repository.htmlURL == URL(string: "https://github.com/drew/last-call"))
        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["remote", "add", "origin", "https://github.com/drew/last-call.git"])
        #expect(invocations[1].arguments == ["config", "user.name", "Drew Calloway"])
        #expect(invocations[2].arguments == ["config", "user.email", "drew@example.com"])
        #expect(invocations[3].arguments == ["push", "-u", "origin", "main"])
    }

    @Test("connectToGitHub falls back to the noreply email when the account has none public")
    func connectToGitHubFallsBackToNoreplyEmail() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 201, jsonObject: [
            "name": "last-call",
            "full_name": "drew/last-call",
            "clone_url": "https://github.com/drew/last-call.git",
            "html_url": "https://github.com/drew/last-call",
            "private": true
        ])
        await requester.script(statusCode: 200, jsonObject: ["login": "drew", "email": NSNull()])
        let coordinator = RepositoryCoordinator(gitService: GitService(processRunner: runner), workingTree: root)

        _ = try await coordinator.connectToGitHub(
            repositoryName: "last-call",
            authorName: "Drew Calloway",
            apiClient: GitHubAPIClient(requester: requester),
            token: "ghp_abc"
        )

        let invocations = await runner.invocations
        #expect(invocations[2].arguments == ["config", "user.email", "drew@users.noreply.github.com"])
    }

    @Test("ensureInitialized runs init and configures identity when .git is missing")
    func ensureInitializedInitsWhenMissing() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let coordinator = RepositoryCoordinator(gitService: GitService(processRunner: runner), workingTree: root)

        try await coordinator.ensureInitialized(authorName: "Drew Calloway")

        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments == ["init", "-b", "main"] })
        #expect(invocations.contains { $0.arguments == ["config", "user.name", "Drew Calloway"] })
        #expect(invocations.contains { $0.arguments.first == "config" && $0.arguments.last == "drew-calloway@drafter.local" })
    }

    @Test("ensureInitialized is a no-op when .git already exists")
    func ensureInitializedNoOpWhenPresent() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let runner = MockProcessRunner()
        let coordinator = RepositoryCoordinator(gitService: GitService(processRunner: runner), workingTree: root)

        try await coordinator.ensureInitialized(authorName: "Drew Calloway")

        let invocations = await runner.invocations
        #expect(invocations.isEmpty)
    }

    @Test("commit stages and commits when there are uncommitted changes")
    func commitStagesAndCommitsWhenDirty() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: " M scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let coordinator = RepositoryCoordinator(
            gitService: GitService(processRunner: runner),
            workingTree: root,
            machineName: "Test-Machine"
        )

        let didCommit = try await coordinator.commit(trigger: .preExport)

        #expect(didCommit == true)
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments).contains(["add", "-A"]))
        #expect(invocations.contains { $0.arguments.first == "commit" && $0.arguments.last?.contains("pre-export") == true })
    }

    @Test("commit is a no-op when there's nothing to commit — never an empty commit")
    func commitNoOpWhenClean() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let coordinator = RepositoryCoordinator(gitService: GitService(processRunner: runner), workingTree: root)

        let didCommit = try await coordinator.commit(trigger: .preExport)

        #expect(didCommit == false)
        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments.first == "commit" } == false)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
