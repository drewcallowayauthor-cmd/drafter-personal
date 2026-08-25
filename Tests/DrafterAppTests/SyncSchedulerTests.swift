import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@MainActor
@Suite("SyncScheduler")
struct SyncSchedulerTests {
    @Test("start runs an immediate sync pass")
    func startRunsImmediateSync() async throws {
        let runner = MockProcessRunner()
        await scriptIdenticalSync(runner)
        let scheduler = makeScheduler(runner: runner, fetchInterval: .seconds(60))

        scheduler.start()
        try await Task.sleep(for: .milliseconds(30))

        #expect(scheduler.state == .idle)
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments.first) == ["fetch", "rev-parse", "rev-list"])
    }

    @Test("the periodic loop runs another sync pass after fetchInterval elapses")
    func periodicLoopRunsAnotherPass() async throws {
        let runner = MockProcessRunner()
        await scriptIdenticalSync(runner)
        await scriptIdenticalSync(runner)
        let scheduler = makeScheduler(runner: runner, fetchInterval: .milliseconds(40))

        scheduler.start()
        try await Task.sleep(for: .milliseconds(100))

        let invocationCount = await runner.invocations.count
        #expect(invocationCount >= 4)
    }

    @Test("stop cancels the periodic loop so no further syncs happen")
    func stopCancelsPeriodicLoop() async throws {
        let runner = MockProcessRunner()
        await scriptIdenticalSync(runner)
        // A generous fetchInterval, well clear of the stop() call below, so this isn't
        // racing the periodic loop's own sleep — under load, a tight margin here is
        // exactly the kind of thing that flakes.
        let scheduler = makeScheduler(runner: runner, fetchInterval: .milliseconds(300))

        scheduler.start()
        try await Task.sleep(for: .milliseconds(20))
        scheduler.stop()
        let countAtStop = await runner.invocations.count

        try await Task.sleep(for: .milliseconds(400))

        let countAfterWaiting = await runner.invocations.count
        #expect(countAfterWaiting == countAtStop)
    }

    @Test("schedulePushAfterCommit debounces: rapid calls only trigger one sync pass")
    func schedulePushAfterCommitDebounces() async throws {
        let runner = MockProcessRunner()
        await scriptIdenticalSync(runner)
        // A generous debounce delay and post-fire wait, well clear of the reschedule
        // below, so this isn't racing the debounce's own sleep — under load, a tight
        // margin here is exactly the kind of thing that flakes.
        let scheduler = makeScheduler(runner: runner, fetchInterval: .seconds(60), pushDebounceDelay: .milliseconds(50))

        scheduler.schedulePushAfterCommit()
        try await Task.sleep(for: .milliseconds(20))
        scheduler.schedulePushAfterCommit()

        try await Task.sleep(for: .milliseconds(300))

        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments.first) == ["fetch", "rev-parse", "rev-list"])
    }

    @Test("syncBeforeClose awaits one final sync pass")
    func syncBeforeCloseAwaitsFinalPass() async throws {
        let runner = MockProcessRunner()
        await scriptIdenticalSync(runner)
        let scheduler = makeScheduler(runner: runner, fetchInterval: .seconds(60))

        await scheduler.syncBeforeClose()

        #expect(scheduler.state == .idle)
    }

    private func scriptIdenticalSync(_ runner: MockProcessRunner) async {
        // fetch
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-parse
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-list
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "0\t0\n", standardError: ""), forExecutableNamed: "git"
        )
    }

    private func makeScheduler(
        runner: MockProcessRunner,
        fetchInterval: Duration,
        pushDebounceDelay: Duration = .seconds(30)
    ) -> SyncScheduler {
        let coordinator = SyncCoordinator(
            gitService: GitService(processRunner: runner),
            workingTree: URL(fileURLWithPath: "/tmp/project"),
            machineName: "Test-Machine"
        )
        return SyncScheduler(
            syncCoordinator: coordinator, fetchInterval: fetchInterval, pushDebounceDelay: pushDebounceDelay
        )
    }
}
