import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import GitService

@Suite("ConflictResolver")
struct ConflictResolverTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")

    @Test("keepMine checks out ours and stages the result")
    func keepMineChecksOutOursAndStages() async throws {
        let runner = MockProcessRunner()
        let resolver = makeResolver(runner: runner)

        try await resolver.keepMine(path: "Manuscript/scene.md")

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["checkout", "--ours", "Manuscript/scene.md"])
        #expect(invocations[1].arguments == ["add", "-A"])
    }

    @Test("keepTheirs checks out theirs and stages the result")
    func keepTheirsChecksOutTheirsAndStages() async throws {
        let runner = MockProcessRunner()
        let resolver = makeResolver(runner: runner)

        try await resolver.keepTheirs(path: "Manuscript/scene.md")

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["checkout", "--theirs", "Manuscript/scene.md"])
        #expect(invocations[1].arguments == ["add", "-A"])
    }

    @Test("keepBoth writes their content to the duplicate path, keeps ours in place, and stages")
    func keepBothWritesDuplicateAndKeepsOurs() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Their version of the scene.\n", standardError: ""),
            forExecutableNamed: "git"
        ) // show :3:path
        let writer = MockAtomicFileWriter()
        let resolver = makeResolver(runner: runner, writer: writer)

        try await resolver.keepBoth(
            path: "Manuscript/scene.md",
            duplicatePath: "Manuscript/scene (from MacBook Pro 2026-08-17).md"
        )

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["show", ":3:Manuscript/scene.md"])
        #expect(invocations[1].arguments == ["checkout", "--ours", "Manuscript/scene.md"])
        #expect(invocations[2].arguments == ["add", "-A"])

        let writes = writer.writes
        #expect(writes.count == 1)
        #expect(
            writes[0].url == workingTree.appendingPathComponent("Manuscript/scene (from MacBook Pro 2026-08-17).md")
        )
        #expect(String(data: writes[0].data, encoding: .utf8) == "Their version of the scene.\n")
    }

    @Test("finalize commits with the machine-labeled message, then pushes")
    func finalizeCommitsThenPushes() async throws {
        let runner = MockProcessRunner()
        let resolver = makeResolver(runner: runner)

        try await resolver.finalize(machineName: "Drew-MacBook-Pro")

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["commit", "-m", "resolve conflicts from Drew-MacBook-Pro"])
        #expect(invocations[1].arguments == ["push", "origin", "main"])
    }

    private func makeResolver(
        runner: MockProcessRunner, writer: MockAtomicFileWriter = MockAtomicFileWriter()
    ) -> ConflictResolver {
        ConflictResolver(
            gitService: GitService(processRunner: runner), atomicFileWriter: writer, workingTree: workingTree
        )
    }
}
