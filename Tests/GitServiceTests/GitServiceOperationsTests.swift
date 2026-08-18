import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import GitService

@Suite("GitService operations")
struct GitServiceOperationsTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")

    @Test("stageAll runs git add -A")
    func stageAllRunsAdd() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.stageAll(in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["add", "-A"])
    }

    @Test("commit passes the message through to git commit -m")
    func commitPassesMessage() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.commit(message: "checkpoint", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["commit", "-m", "checkpoint"])
    }

    @Test("fetch defaults to origin")
    func fetchDefaultsToOrigin() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.fetch(in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["fetch", "origin"])
    }

    @Test("fastForwardMerge runs merge --ff-only")
    func fastForwardMergeRunsFFOnly() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.fastForwardMerge(to: "origin/main", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["merge", "--ff-only", "origin/main"])
    }

    @Test("push defaults to origin main")
    func pushDefaultsToOriginMain() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.push(in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["push", "origin", "main"])
    }

    @Test("a clean merge returns .clean without inspecting conflicts")
    func cleanMergeReturnsClean() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        let result = try await service.merge(with: "origin/main", in: workingTree)

        #expect(result == .clean)
    }

    @Test("a conflicted merge returns .conflicted with the file list, not a thrown error")
    func conflictedMergeReturnsConflictedPaths() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "CONFLICT (content): Merge conflict"),
            forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(
                exitCode: 0,
                standardOutput: "Manuscript/02 The First Hour/02 Code Blue.md\n",
                standardError: ""
            ),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let result = try await service.merge(with: "origin/main", in: workingTree)

        #expect(result == .conflicted(paths: ["Manuscript/02 The First Hour/02 Code Blue.md"]))
    }

    @Test("a non-zero merge exit with no conflicted files throws instead of silently succeeding")
    func nonConflictMergeFailureThrows() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 128, standardOutput: "", standardError: "fatal: not something we can merge"),
            forExecutableNamed: "git"
        )
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        await #expect(throws: DrafterError.self) {
            try await service.merge(with: "origin/main", in: workingTree)
        }
    }

    @Test("keepOurs and keepTheirs run the corresponding checkout flags")
    func keepOursAndKeepTheirs() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.keepOurs(path: "scene.md", in: workingTree)
        try await service.keepTheirs(path: "scene.md", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["checkout", "--ours", "scene.md"])
        #expect(invocations[1].arguments == ["checkout", "--theirs", "scene.md"])
    }

    @Test("move runs git mv so rename history is preserved")
    func moveRunsGitMv() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.move(from: "01 Old.md", to: "02 Old.md", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["mv", "01 Old.md", "02 Old.md"])
    }
}
