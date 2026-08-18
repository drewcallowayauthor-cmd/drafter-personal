import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import GitService

@Suite("GitService repository")
struct GitServiceRepositoryTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/project")
    private let logFormat = "--format=%H%x1f%at%x1f%s%x1f%an%x1f%(trailers:key=Machine,valueonly=true,separator=)"

    @Test("initRepository runs git init -b main")
    func initRepositoryRunsGitInit() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.initRepository(in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["init", "-b", "main"])
    }

    @Test("configureIdentity sets both user.name and user.email, scoped locally")
    func configureIdentitySetsNameAndEmail() async throws {
        let runner = MockProcessRunner()
        let service = GitService(processRunner: runner)

        try await service.configureIdentity(name: "Tim Fleet", email: "tim@example.com", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations[0].arguments == ["config", "user.name", "Tim Fleet"])
        #expect(invocations[1].arguments == ["config", "user.email", "tim@example.com"])
    }

    @Test("log with a path includes --follow and the path filter")
    func logWithPathIncludesFollowAndFilter() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        _ = try await service.log(for: "Manuscript/01 Arrival/01 Triage.md", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == [
            "log", "--follow", logFormat, "--", "Manuscript/01 Arrival/01 Triage.md"
        ])
    }

    @Test("log without a path omits --follow for the project-wide timeline")
    func logWithoutPathOmitsFollow() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        _ = try await service.log(in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["log", logFormat])
    }

    @Test("log parses multiple commits into ordered entries, including the machine trailer")
    func logParsesMultipleCommits() async throws {
        let runner = MockProcessRunner()
        let output = [
            "abc123\u{1F}1755000000\u{1F}autosave — 1 file, +50 words\u{1F}Josiah Massari\u{1F}Josiah-MacBook-Pro",
            "def456\u{1F}1754900000\u{1F}checkpoint\u{1F}Josiah Massari\u{1F}Josiah-Mac-Studio"
        ].joined(separator: "\n") + "\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        let entries = try await service.log(in: workingTree)

        #expect(entries.count == 2)
        #expect(entries[0].sha == "abc123")
        #expect(entries[0].subject == "autosave — 1 file, +50 words")
        #expect(entries[0].authorName == "Josiah Massari")
        #expect(entries[0].machineName == "Josiah-MacBook-Pro")
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_755_000_000))
        #expect(entries[1].sha == "def456")
        #expect(entries[1].machineName == "Josiah-Mac-Studio")
    }

    @Test("log tolerates an empty machine field for commits made outside the app")
    func logToleratesEmptyMachineField() async throws {
        let runner = MockProcessRunner()
        let output = "abc123\u{1F}1755000000\u{1F}Initial commit\u{1F}Josiah Massari\u{1F}\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        let entries = try await service.log(in: workingTree)

        #expect(entries.count == 1)
        #expect(entries[0].machineName == "")
    }

    @Test("log on an empty repository returns no entries rather than throwing")
    func logOnEmptyRepositoryReturnsEmpty() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        let entries = try await service.log(in: workingTree)

        #expect(entries.isEmpty)
    }

    @Test("log skips a malformed line instead of throwing")
    func logSkipsMalformedLine() async throws {
        let runner = MockProcessRunner()
        let output = "not-enough-fields\u{1F}only-two\n"
        await runner.script(ProcessResult(exitCode: 0, standardOutput: output, standardError: ""), forExecutableNamed: "git")
        let service = GitService(processRunner: runner)

        let entries = try await service.log(in: workingTree)

        #expect(entries.isEmpty)
    }

    @Test("show runs git show <sha>:<path> and returns its output")
    func showRunsGitShow() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "---\nstatus: draft\n---\n\nOlder text.", standardError: ""),
            forExecutableNamed: "git"
        )
        let service = GitService(processRunner: runner)

        let contents = try await service.show(path: "Manuscript/01 Arrival/01 Triage.md", at: "abc123", in: workingTree)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["show", "abc123:Manuscript/01 Arrival/01 Triage.md"])
        #expect(contents == "---\nstatus: draft\n---\n\nOlder text.")
    }
}
