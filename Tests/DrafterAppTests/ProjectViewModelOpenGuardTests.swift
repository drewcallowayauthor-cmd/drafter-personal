import DrafterCore
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

/// §12.2 point 7: opening the same project in two windows must not attach two
/// independent sets of git/FSEvents watchers to one working tree.
@Suite("ProjectViewModel open guard", .serialized)
@MainActor
struct ProjectViewModelOpenGuardTests {
    @Test("a second window opening an already-open project is refused, not attached")
    func refusesOpeningAnAlreadyOpenProject() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstWindow = ProjectViewModel()
        await firstWindow.open(root: root)
        #expect(firstWindow.errorMessage == nil)
        #expect(firstWindow.binderTree != nil)

        let secondWindow = ProjectViewModel()
        await secondWindow.open(root: root)

        #expect(secondWindow.errorMessage != nil)
        #expect(secondWindow.binderTree == nil)
        #expect(secondWindow.autocommitScheduler == nil)

        // The first window's own project is untouched by the second window's failed attempt.
        #expect(firstWindow.binderTree != nil)

        await firstWindow.closeProject()
    }

    @Test("closing the first window's project frees the root for a second window to open")
    func closingFreesTheRootForAnotherWindow() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstWindow = ProjectViewModel()
        await firstWindow.open(root: root)
        await firstWindow.closeProject()

        let secondWindow = ProjectViewModel()
        await secondWindow.open(root: root)

        #expect(secondWindow.errorMessage == nil)
        #expect(secondWindow.binderTree != nil)

        await secondWindow.closeProject()
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chapterDirectory = root.appendingPathComponent("Manuscript/01 Arrival")
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        try Data("Text.".utf8).write(to: chapterDirectory.appendingPathComponent("01 Triage.md"))

        // Local-file mode deliberately, even though this suite has nothing to do with
        // version control: what's under test is `OpenProjectRegistry`'s double-open
        // guard, and Git mode's `attach()` path spawns real `git init`/`config`
        // subprocesses and a real Keychain lookup (§12.2 point 7) — both slow and,
        // under this suite's `.serialized` parallelism with the rest of the test
        // binary, prone to real-world contention that turned "slow" into "effectively
        // hung." Local-file mode exercises the exact same registry guard through pure
        // file I/O.
        let metadata = ProjectMetadata(
            title: "The Last Shift",
            author: "Tim Fleet",
            versionControl: .localFile,
            copyrightYear: 2026
        )
        let store = ProjectMetadataStore(fileWriter: LiveAtomicFileWriter())
        try store.save(metadata, to: root)

        return root
    }
}
