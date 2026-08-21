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

    @Test("concurrent open and close calls serialize instead of interleaving and corrupting state")
    func concurrentOpenAndCloseSerialize() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let vm = ProjectViewModel()

        // Fired without awaiting either first. This asserts the invariant
        // `serialized()` is meant to guarantee — `open`'s `attach()` and
        // `closeProject`'s `reset()` never interleave, so state is never left torn
        // between them. Note: Local-file mode's `attach()` has no real network
        // `await` gap wide enough for cooperative scheduling to actually interleave
        // these two calls in practice, so this test doesn't reproduce the historical
        // bug (which needed a slow Git-mode network fetch mid-`attach()` to open the
        // window) — it's a standing invariant check, not a reproduction.
        async let openCall: Void = vm.open(root: root)
        async let closeCall: Void = vm.closeProject()
        _ = await (openCall, closeCall)

        // Whichever actually ran last, the result must be internally consistent: an
        // "open" project always has both set; a "closed" one has neither torn apart.
        if vm.binderTree != nil {
            #expect(vm.autocommitScheduler != nil)
        } else {
            #expect(vm.autocommitScheduler == nil)
        }

        // No orphaned registry lock either way — a fresh window can still open the
        // same root once this settles.
        if vm.binderTree == nil {
            let secondWindow = ProjectViewModel()
            await secondWindow.open(root: root)
            #expect(secondWindow.errorMessage == nil)
            await secondWindow.closeProject()
        }

        await vm.closeProject()
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
