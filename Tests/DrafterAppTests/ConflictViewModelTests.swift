import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@MainActor
@Suite("ConflictViewModel")
struct ConflictViewModelTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")

    @Test("starts with one unresolved FileConflict per path, allResolved false")
    func startsUnresolved() {
        let viewModel = makeViewModel(paths: ["Manuscript/a.md", "Manuscript/b.md"], runner: MockProcessRunner())

        #expect(viewModel.conflicts.map(\.path) == ["Manuscript/a.md", "Manuscript/b.md"])
        #expect(viewModel.conflicts.allSatisfy { !$0.isResolved })
        #expect(viewModel.allResolved == false)
    }

    @Test("keepMine checks out ours and marks the path resolved")
    func keepMineMarksResolved() async throws {
        let runner = MockProcessRunner()
        let viewModel = makeViewModel(paths: ["Manuscript/a.md"], runner: runner)

        await viewModel.keepMine(viewModel.conflicts[0])

        #expect(viewModel.conflicts[0].isResolved == true)
        #expect(viewModel.allResolved == true)
        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments == ["checkout", "--ours", "Manuscript/a.md"] })
    }

    @Test("keepBoth writes the duplicate using theirs' machine and date")
    func keepBothNamesDuplicateFromTheirsMetadata() async throws {
        let runner = MockProcessRunner()
        // theirsContent lookup for keepBoth's write (`show :3:path`)
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Their text.", standardError: ""),
            forExecutableNamed: "git"
        )
        let viewModel = makeViewModel(paths: ["Manuscript/a.md"], runner: runner, atomicFileWriter: MockAtomicFileWriter())
        var conflict = viewModel.conflicts[0]
        conflict.theirs = CommitLogEntry(
            sha: "abc",
            date: Date(timeIntervalSince1970: 1_755_000_000),
            subject: "checkpoint",
            authorName: "Josiah",
            machineName: "Josiah-MacBook-Pro"
        )

        await viewModel.keepBoth(conflict)

        let invocations = await runner.invocations
        // keepBoth: show :3:path, then checkout --ours, then add -A
        #expect(invocations.contains { $0.arguments == ["checkout", "--ours", "Manuscript/a.md"] })
        #expect(viewModel.conflicts[0].isResolved == true)
    }

    @Test("finalize is a no-op returning false until every conflict is resolved")
    func finalizeRefusesUntilAllResolved() async throws {
        let runner = MockProcessRunner()
        let viewModel = makeViewModel(paths: ["Manuscript/a.md", "Manuscript/b.md"], runner: runner)

        let succeeded = await viewModel.finalize()

        #expect(succeeded == false)
        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments.first == "commit" } == false)
    }

    @Test("finalize commits and pushes once everything is resolved")
    func finalizeCommitsAndPushesWhenAllResolved() async throws {
        let runner = MockProcessRunner()
        let viewModel = makeViewModel(paths: ["Manuscript/a.md"], runner: runner, machineName: "Josiah-Mac-Studio")
        await viewModel.keepMine(viewModel.conflicts[0])

        let succeeded = await viewModel.finalize()

        #expect(succeeded == true)
        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments == ["commit", "-m", "resolve conflicts from Josiah-Mac-Studio"] })
        #expect(invocations.contains { $0.arguments == ["push", "origin", "main"] })
    }

    private func makeViewModel(
        paths: [String],
        runner: MockProcessRunner,
        machineName: String = "Test-Machine",
        atomicFileWriter: MockAtomicFileWriter = MockAtomicFileWriter()
    ) -> ConflictViewModel {
        ConflictViewModel(
            paths: paths,
            gitService: GitService(processRunner: runner),
            workingTree: workingTree,
            machineName: machineName,
            atomicFileWriter: atomicFileWriter
        )
    }
}
