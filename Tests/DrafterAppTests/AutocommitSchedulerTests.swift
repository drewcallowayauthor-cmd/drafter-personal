import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@MainActor
@Suite("AutocommitScheduler")
struct AutocommitSchedulerTests {
    @Test("does not commit before the debounce elapses")
    func doesNotCommitBeforeDebounce() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: " M scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let scheduler = makeScheduler(root: root, runner: runner, delay: .milliseconds(100))

        scheduler.recordActivity(wordDelta: 10)
        try await Task.sleep(for: .milliseconds(30))

        let invocations = await runner.invocations
        #expect(invocations.contains { $0.arguments.first == "commit" } == false)
    }

    @Test("commits with the accumulated word delta once the debounce elapses")
    func commitsWithAccumulatedDeltaAfterDebounce() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: " M scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let scheduler = makeScheduler(root: root, runner: runner, delay: .milliseconds(50))

        scheduler.recordActivity(wordDelta: 10)
        try await Task.sleep(for: .milliseconds(20))
        scheduler.recordActivity(wordDelta: 5)

        try await Task.sleep(for: .milliseconds(150))

        let invocations = await runner.invocations
        let commitArgs = invocations.first { $0.arguments.first == "commit" }?.arguments
        #expect(commitArgs?.last?.contains("+15 words") == true)
    }

    @Test("flush commits immediately and cancels a pending debounce")
    func flushCommitsImmediately() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: " M scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let scheduler = makeScheduler(root: root, runner: runner, delay: .seconds(60))

        scheduler.recordActivity(wordDelta: 10)
        await scheduler.flush(trigger: .focusLost)

        let invocations = await runner.invocations
        let commitArgs = invocations.first { $0.arguments.first == "commit" }?.arguments
        #expect(commitArgs?.last?.contains("focus lost") == true)

        // The debounced autosave that was pending should not also fire later.
        try await Task.sleep(for: .milliseconds(50))
        let commitCount = await runner.invocations.filter { $0.arguments.first == "commit" }.count
        #expect(commitCount == 1)
    }

    @Test("does not commit when there is nothing dirty")
    func doesNotCommitWhenClean() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let scheduler = makeScheduler(root: root, runner: runner, delay: .milliseconds(30))

        scheduler.recordActivity(wordDelta: 0)
        try await Task.sleep(for: .milliseconds(100))

        let commitCount = await runner.invocations.filter { $0.arguments.first == "commit" }.count
        #expect(commitCount == 0)
    }

    private func makeScheduler(root: URL, runner: MockProcessRunner, delay: Duration) -> AutocommitScheduler {
        let coordinator = RepositoryCoordinator(
            gitService: GitService(processRunner: runner),
            workingTree: root,
            machineName: "Test-Machine"
        )
        return AutocommitScheduler(checkpointCoordinator: coordinator, debounceDelay: delay)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
