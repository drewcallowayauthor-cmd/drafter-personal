import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import GitService

@Suite("SyncCoordinator")
struct SyncCoordinatorTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")

    @Test("identical to remote: fetches, sees no divergence, lands on idle")
    func identicalLandsOnIdle() async throws {
        let runner = MockProcessRunner()
        // fetch
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-parse (branch exists)
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-list
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "0\t0\n", standardError: ""), forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .idle)
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments.first) == ["fetch", "rev-parse", "rev-list"])
    }

    @Test("behind only: fast-forwards and lands on idle")
    func behindOnlyFastForwards() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "0\t3\n", standardError: ""), forExecutableNamed: "git"
        )
        // ff merge
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .idle)
        let invocations = await runner.invocations
        #expect(invocations[3].arguments == ["merge", "--ff-only", "origin/main"])
    }

    @Test("ahead only: pushes and lands on idle, without ever merging")
    func aheadOnlyPushes() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "2\t0\n", standardError: ""), forExecutableNamed: "git"
        )
        // push
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .idle)
        let invocations = await runner.invocations
        #expect(invocations[3].arguments == ["push", "-u", "origin", "main"])
    }

    @Test("no remote branch yet: pushes directly without attempting divergence (§5.2 bootstrap / self-heal)")
    func noRemoteBranchYetPushesDirectly() async throws {
        let runner = MockProcessRunner()
        // fetch
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: ""),
            forExecutableNamed: "git"
        ) // rev-parse: no such ref
        // push -u
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .idle)
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments.first) == ["fetch", "rev-parse", "push"])
        #expect(invocations[2].arguments == ["push", "-u", "origin", "main"])
    }

    @Test("diverged with a clean merge: merges with a labeled message, then pushes")
    func divergedCleanMergePushes() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "1\t1\n", standardError: ""), forExecutableNamed: "git"
        )
        // merge
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // push
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .idle)
        let invocations = await runner.invocations
        #expect(invocations[3].arguments == ["merge", "origin/main", "-m", "merge from Test-Machine"])
        #expect(invocations[4].arguments == ["push", "-u", "origin", "main"])
    }

    @Test("a clean merge then a failed push reports the merge commit in pendingCommits, not the stale ahead count")
    func divergedCleanMergeThenFailedPushCountsTheMergeCommit() async throws {
        let runner = MockProcessRunner()
        // fetch
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-parse
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        // rev-list: ahead 2, behind 3
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "2\t3\n", standardError: ""), forExecutableNamed: "git"
        )
        // merge (clean)
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "network unreachable"),
            forExecutableNamed: "git"
        ) // push fails
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        // Pre-merge ahead count was 2; the merge itself adds one more local commit,
        // so a push failure right after should report 3 pending, not 2.
        #expect(finalState == .offline(pendingCommits: 3))
    }

    @Test("diverged with a conflicting merge: lands on conflicted with the file list, never pushes")
    func divergedConflictedMergeStops() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "1\t1\n", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "CONFLICT"),
            forExecutableNamed: "git"
        ) // merge fails
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Manuscript/scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        ) // diff --name-only --diff-filter=U
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .conflicted(paths: ["Manuscript/scene.md"]))
        let invocations = await runner.invocations
        #expect(invocations.map(\.arguments.first) == ["fetch", "rev-parse", "rev-list", "merge", "diff"])
    }

    @Test("a failed fetch resolves to offline instead of throwing")
    func failedFetchResolvesToOffline() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "fatal: could not resolve host"),
            forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .offline(pendingCommits: 0))
    }

    @Test("a fetch rejected for bad credentials resolves to authenticationRequired, not offline")
    func authFailureOnFetchResolvesToAuthenticationRequired() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(
                exitCode: 128,
                standardOutput: "",
                standardError: "remote: invalid credentials\n"
                    + "fatal: Authentication failed for 'https://github.com/drew/book.git/'\n"
            ),
            forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .authenticationRequired)
    }

    @Test("a push rejected for bad credentials resolves to authenticationRequired, not offline")
    func authFailureOnPushResolvesToAuthenticationRequired() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "2\t0\n", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(
                exitCode: 128,
                standardOutput: "",
                standardError: "remote: Invalid username or token.\n"
                    + "fatal: Authentication failed for 'https://github.com/drew/book.git/'\n"
            ),
            forExecutableNamed: "git"
        ) // push
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .authenticationRequired)
    }

    @Test("a rejected push resolves to offline, carrying the ahead count as pending commits")
    func rejectedPushResolvesToOffline() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "2\t0\n", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "! [rejected]"),
            forExecutableNamed: "git"
        ) // push
        let coordinator = makeCoordinator(runner: runner)

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .offline(pendingCommits: 2))
    }

    @Test("once conflicted, further syncNow calls are a no-op until resolved")
    func conflictedShortCircuitsFurtherCalls() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "1\t1\n", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "CONFLICT"),
            forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Manuscript/scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)
        _ = try await coordinator.syncNow()
        let invocationCountAfterConflict = await runner.invocations.count

        let finalState = try await coordinator.syncNow()

        #expect(finalState == .conflicted(paths: ["Manuscript/scene.md"]))
        let invocations = await runner.invocations
        #expect(invocations.count == invocationCountAfterConflict)
    }

    @Test("markConflictResolved clears .conflicted back to .idle without touching git")
    func markConflictResolvedClearsToIdle() async throws {
        let runner = MockProcessRunner()
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
            ProcessResult(exitCode: 0, standardOutput: "1\t1\n", standardError: ""), forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "CONFLICT"),
            forExecutableNamed: "git"
        )
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Manuscript/scene.md\n", standardError: ""),
            forExecutableNamed: "git"
        )
        let coordinator = makeCoordinator(runner: runner)
        _ = try await coordinator.syncNow()
        let invocationCountAfterConflict = await runner.invocations.count

        let resolvedState = try await coordinator.markConflictResolved()

        #expect(resolvedState == .idle)
        let invocations = await runner.invocations
        #expect(invocations.count == invocationCountAfterConflict)
    }

    private func makeCoordinator(runner: MockProcessRunner) -> SyncCoordinator {
        SyncCoordinator(
            gitService: GitService(processRunner: runner),
            workingTree: workingTree,
            machineName: "Test-Machine"
        )
    }
}
