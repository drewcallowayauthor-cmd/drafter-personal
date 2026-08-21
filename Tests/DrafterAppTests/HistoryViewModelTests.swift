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

    @Test("a slow load for a scene that's no longer selected doesn't overwrite the newer selection's entries")
    func staleSlowerLoadDoesNotOverwriteNewerSelection() async throws {
        let firstScene = workingTree.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let secondScene = workingTree.appendingPathComponent("Manuscript/01 Arrival/02 Standoff.md")
        let source = DelayedVersioningSource(delayedPath: "Manuscript/01 Arrival/01 Triage.md", delayMilliseconds: 50)
        let viewModel = HistoryViewModel(source: source)

        // Mirrors `.task(id: sceneURL)`: switch scenes before the first (slower)
        // load resolves, then cancel it — matching what SwiftUI actually does when
        // `sceneURL` changes. `DelayedVersioningSource`'s delay deliberately ignores
        // Task cancellation (via a raw `DispatchQueue` timer, not `Task.sleep`), the
        // same way a real subprocess wait (`Process.terminationHandler`) does — so
        // this reproduces the actual failure mode: the cancelled load still resolves
        // successfully, just later, and must not be allowed to clobber the newer one.
        let firstLoad = Task { await viewModel.load(sceneURL: firstScene, workingTree: workingTree) }
        try await Task.sleep(for: .milliseconds(5))
        firstLoad.cancel()
        await viewModel.load(sceneURL: secondScene, workingTree: workingTree)
        _ = await firstLoad.value

        #expect(viewModel.entries.map(\.subject) == ["second scene"])
    }
}

/// A `VersioningSource` fake whose `log(for:)` can be made slower for one specific
/// path, so a test can force a "started first but resolves last" ordering.
private struct DelayedVersioningSource: VersioningSource {
    let delayedPath: String
    let delayMilliseconds: Int

    func log(for path: String?, in workingTree: URL) async throws -> [CommitLogEntry] {
        if path == delayedPath {
            // Deliberately not `Task.sleep`, which throws immediately on cancellation
            // — that would make this test pass for the wrong reason (an early throw,
            // never reaching the success path this test needs to exercise). A raw
            // `DispatchQueue` timer ignores Task cancellation entirely, the same way
            // `LiveProcessRunner`'s subprocess-termination continuation does.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMilliseconds)) {
                    continuation.resume()
                }
            }
            return [CommitLogEntry(sha: "first", date: Date(), subject: "first scene", authorName: "Tim Fleet", machineName: "Machine-1")]
        }
        return [CommitLogEntry(sha: "second", date: Date(), subject: "second scene", authorName: "Tim Fleet", machineName: "Machine-1")]
    }

    func show(path: String, at id: String, in workingTree: URL) async throws -> String { "" }
}
