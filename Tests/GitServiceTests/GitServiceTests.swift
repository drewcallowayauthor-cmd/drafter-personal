import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import GitService

@Suite("GitService")
struct GitServiceTests {
    @Test("empty porcelain output means no uncommitted changes")
    func noUncommittedChanges() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let hasChanges = try await service.hasUncommittedChanges(in: URL(fileURLWithPath: "/tmp/project"))

        #expect(hasChanges == false)
        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["status", "--porcelain"])
    }

    @Test("non-empty porcelain output means uncommitted changes")
    func hasUncommittedChanges() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: " M Manuscript/scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let hasChanges = try await service.hasUncommittedChanges(in: URL(fileURLWithPath: "/tmp/project"))

        #expect(hasChanges == true)
    }

    @Test("repositorySize returns the trimmed count-objects output")
    func repositorySizeReturnsTrimmedOutput() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "count: 12\nsize: 1.02 MiB\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let size = try await service.repositorySize(workingTree: URL(fileURLWithPath: "/tmp/project"))

        #expect(size == "count: 12\nsize: 1.02 MiB")
        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["count-objects", "-vH"])
    }

    @Test("runMaintenance invokes git gc")
    func runMaintenanceInvokesGitGC() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        try await service.runMaintenance(workingTree: URL(fileURLWithPath: "/tmp/project"))

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["gc"])
    }

    @Test("parses ahead/behind counts from rev-list")
    func parsesDivergence() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "2\t5\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let divergence = try await service.divergence(from: "origin/main", in: URL(fileURLWithPath: "/tmp/project"))

        #expect(divergence.ahead == 2)
        #expect(divergence.behind == 5)
    }

    @Test("non-zero exit surfaces as processFailed with stderr")
    func nonZeroExitSurfacesError() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 128, standardOutput: "", standardError: "fatal: not a git repository"),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        await #expect(throws: DrafterError.self) {
            try await service.hasUncommittedChanges(in: URL(fileURLWithPath: "/tmp/project"))
        }
    }

    @Test("sets GIT_TERMINAL_PROMPT=0 so git never hangs on a credential prompt")
    func neverPromptsForCredentials() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        _ = try await service.hasUncommittedChanges(in: URL(fileURLWithPath: "/tmp/project"))

        let invocations = await runner.invocations
        #expect(invocations.first?.environment?["GIT_TERMINAL_PROMPT"] == "0")
    }
}
