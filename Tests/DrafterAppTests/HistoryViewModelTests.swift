import DrafterCore
import DrafterTestSupport
import Foundation
import GitService
import Testing
@testable import DrafterApp

@MainActor
@Suite("HistoryViewModel")
struct HistoryViewModelTests {
    private let workingTree = URL(fileURLWithPath: "/tmp/The Last Shift")

    @Test("relativePath strips the working tree prefix")
    func relativePathStripsPrefix() {
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        #expect(HistoryViewModel.relativePath(of: sceneURL, in: workingTree) == "Manuscript/01 Arrival/01 Triage.md")
    }

    @Test("load fetches log scoped to the scene's relative path")
    func loadFetchesLogForRelativePath() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(
                exitCode: 0,
                standardOutput: "abc\u{1F}1755000000\u{1F}autosave — 1 file, +10 words\u{1F}Tim Fleet\u{1F}Machine-1\n",
                standardError: ""
            ),
            forExecutableNamed: "git"
        )
        let viewModel = HistoryViewModel(gitService: GitService(processRunner: runner))
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")

        await viewModel.load(sceneURL: sceneURL, workingTree: workingTree)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries.first?.subject == "autosave — 1 file, +10 words")
        let invocations = await runner.invocations
        #expect(invocations.first?.arguments.last == "Manuscript/01 Arrival/01 Triage.md")
    }

    @Test("restoreAsCopy writes the older content alongside the scene, not over it")
    func restoreAsCopyWritesSibling() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Older text.", standardError: ""),
            forExecutableNamed: "git"
        )
        let writer = MockAtomicFileWriter()
        let viewModel = HistoryViewModel(gitService: GitService(processRunner: runner), fileWriter: writer)
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let entry = CommitLogEntry(
            sha: "abc123",
            date: Date(timeIntervalSince1970: 1_755_000_000),
            subject: "autosave — 1 file, +10 words",
            authorName: "Tim Fleet",
            machineName: "Machine-1"
        )

        await viewModel.restoreAsCopy(entry: entry, sceneURL: sceneURL, workingTree: workingTree)

        #expect(writer.writes.count == 1)
        #expect(writer.writes.first?.url.lastPathComponent.hasPrefix("01 Triage (restored ") == true)
        #expect(writer.writes.first?.url.lastPathComponent.hasSuffix(").md") == true)
        #expect(writer.writes.first.map { String(data: $0.data, encoding: .utf8) } == "Older text.")
        #expect(viewModel.restoredFileURL != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a failed restore surfaces an error instead of throwing")
    func failedRestoreSurfacesError() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            throwing: DrafterError.processFailed(command: "git show", exitCode: 128, stderr: "bad object"),
            forExecutableNamed: "git"
        )
        let viewModel = HistoryViewModel(gitService: GitService(processRunner: runner), fileWriter: MockAtomicFileWriter())
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let entry = CommitLogEntry(
            sha: "deadbeef",
            date: Date(),
            subject: "checkpoint",
            authorName: "Tim Fleet",
            machineName: "Machine-1"
        )

        await viewModel.restoreAsCopy(entry: entry, sceneURL: sceneURL, workingTree: workingTree)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.restoredFileURL == nil)
    }
}
