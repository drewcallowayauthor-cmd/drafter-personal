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
        let viewModel = HistoryViewModel(source: GitService(processRunner: runner))
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")

        await viewModel.load(sceneURL: sceneURL, workingTree: workingTree)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries.first?.subject == "autosave — 1 file, +10 words")
        let invocations = await runner.invocations
        #expect(invocations.first?.arguments.last == "Manuscript/01 Arrival/01 Triage.md")
    }

    @Test("loading a second scene with no history doesn't leave the first scene's entries behind")
    func loadingDifferentSceneDoesNotLeaveStaleEntries() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(
                exitCode: 0,
                standardOutput: "abc\u{1F}1755000000\u{1F}checkpoint\u{1F}Tim Fleet\u{1F}Machine-1\n",
                standardError: ""
            ),
            forExecutableNamed: "git"
        )
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "git")
        let viewModel = HistoryViewModel(source: GitService(processRunner: runner))
        let firstScene = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let secondScene = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage (restored).md")

        await viewModel.load(sceneURL: firstScene, workingTree: workingTree)
        #expect(viewModel.entries.count == 1)

        await viewModel.load(sceneURL: secondScene, workingTree: workingTree)

        // The untracked/never-committed second scene must not still show the first
        // scene's commit — that mismatch (an old sha paired with a different path) is
        // exactly what produced git show's "exists on disk, but not in <sha>" error.
        #expect(viewModel.entries.isEmpty)
    }

    @Test("a failed diff sets actionErrorMessage, not errorMessage — the list must stay visible")
    func failedDiffDoesNotBlankTheList() async throws {
        let runner = MockProcessRunner()
        // Both responses queued up front, in call order (log, then show) — the mock
        // replays its last response once more on an empty queue before a newly
        // appended script takes effect, so scripting the throw only after the first
        // call already ran would let the stale success answer the second call instead.
        await runner.script(
            ProcessResult(
                exitCode: 0,
                standardOutput: "abc\u{1F}1755000000\u{1F}checkpoint\u{1F}Tim Fleet\u{1F}Machine-1\n",
                standardError: ""
            ),
            forExecutableNamed: "git"
        )
        await runner.script(
            throwing: DrafterError.processFailed(command: "git show", exitCode: 128, stderr: "bad object"),
            forExecutableNamed: "git"
        )
        let viewModel = HistoryViewModel(source: GitService(processRunner: runner))
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        await viewModel.load(sceneURL: sceneURL, workingTree: workingTree)
        #expect(viewModel.entries.count == 1)

        let entry = viewModel.entries[0]
        let lines = await viewModel.diffLines(against: entry, sceneURL: sceneURL, workingTree: workingTree, currentBody: "x")

        #expect(lines == nil)
        #expect(viewModel.actionErrorMessage != nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.entries.count == 1)
    }

    @Test("restoreAsCopy writes the older content alongside the scene, not over it")
    func restoreAsCopyWritesSibling() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "Older text.", standardError: ""),
            forExecutableNamed: "git"
        )
        let writer = MockAtomicFileWriter()
        let viewModel = HistoryViewModel(source: GitService(processRunner: runner), fileWriter: writer)
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
        #expect(viewModel.actionErrorMessage == nil)
    }

    @Test("a failed restore surfaces an error instead of throwing")
    func failedRestoreSurfacesError() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            throwing: DrafterError.processFailed(command: "git show", exitCode: 128, stderr: "bad object"),
            forExecutableNamed: "git"
        )
        let viewModel = HistoryViewModel(source: GitService(processRunner: runner), fileWriter: MockAtomicFileWriter())
        let sceneURL = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let entry = CommitLogEntry(
            sha: "deadbeef",
            date: Date(),
            subject: "checkpoint",
            authorName: "Tim Fleet",
            machineName: "Machine-1"
        )

        await viewModel.restoreAsCopy(entry: entry, sceneURL: sceneURL, workingTree: workingTree)

        #expect(viewModel.actionErrorMessage != nil)
        #expect(viewModel.restoredFileURL == nil)
    }
}
