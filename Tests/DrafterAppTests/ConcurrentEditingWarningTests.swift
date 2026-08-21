import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@Suite("ConcurrentEditingWarning")
struct ConcurrentEditingWarningTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")
    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    @Test("finds a recent commit from a different machine within the window")
    func findsRecentCommitFromDifferentMachine() async throws {
        let runner = MockProcessRunner()
        let output = "abc\u{1F}\(Int(now.timeIntervalSince1970 - 40))\u{1F}autosave\u{1F}Josiah\u{1F}Josiah-MacBook-Pro\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let gitService = GitService(processRunner: runner)

        let info = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTree,
            ownMachineName: "Josiah-Mac-Studio",
            now: now
        )

        #expect(info == .init(machineName: "Josiah-MacBook-Pro", secondsAgo: 40))
    }

    @Test("ignores commits from its own machine")
    func ignoresOwnMachine() async throws {
        let runner = MockProcessRunner()
        let output = "abc\u{1F}\(Int(now.timeIntervalSince1970 - 40))\u{1F}autosave\u{1F}Josiah\u{1F}Josiah-Mac-Studio\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let gitService = GitService(processRunner: runner)

        let info = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTree,
            ownMachineName: "Josiah-Mac-Studio",
            now: now
        )

        #expect(info == nil)
    }

    @Test("ignores commits older than the window")
    func ignoresOldCommits() async throws {
        let runner = MockProcessRunner()
        let output = "abc\u{1F}\(Int(now.timeIntervalSince1970 - 600))\u{1F}autosave\u{1F}Josiah\u{1F}Josiah-MacBook-Pro\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let gitService = GitService(processRunner: runner)

        let info = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTree,
            ownMachineName: "Josiah-Mac-Studio",
            window: 300,
            now: now
        )

        #expect(info == nil)
    }

    @Test("ignores commits with no machine trailer (made outside the app)")
    func ignoresCommitsWithNoMachineTrailer() async throws {
        let runner = MockProcessRunner()
        let output = "abc\u{1F}\(Int(now.timeIntervalSince1970 - 40))\u{1F}manual edit\u{1F}Someone\u{1F}\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let gitService = GitService(processRunner: runner)

        let info = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTree,
            ownMachineName: "Josiah-Mac-Studio",
            now: now
        )

        #expect(info == nil)
    }

    @Test("a failed log resolves to nil rather than throwing")
    func failedLogResolvesToNil() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 128, standardOutput: "", standardError: "fatal: no such ref"),
            forExecutableNamed: "git"
        )
        let gitService = GitService(processRunner: runner)

        let info = await ConcurrentEditingWarning.check(
            gitService: gitService,
            workingTree: workingTree,
            ownMachineName: "Josiah-Mac-Studio",
            now: now
        )

        #expect(info == nil)
    }
}
