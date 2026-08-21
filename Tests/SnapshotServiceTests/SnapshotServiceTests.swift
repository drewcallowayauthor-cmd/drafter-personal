import DrafterCore
import Foundation
import Testing
@testable import SnapshotService

@Suite("SnapshotService")
struct SnapshotServiceTests {
    private func makeWorkingTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manuscript = root.appendingPathComponent("Manuscript")
        try FileManager.default.createDirectory(at: manuscript, withIntermediateDirectories: true)
        try Data("Once upon a time.".utf8).write(to: manuscript.appendingPathComponent("01 Scene.md"))
        return root
    }

    @Test("createSnapshot copies the working tree into a new History/ folder")
    func createsSnapshot() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        let created = try await service.createSnapshot(
            trigger: .checkpoint(label: "initial"),
            machineName: "Test-Machine",
            in: root
        )

        #expect(created)
        let historyContents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("History").path)
        #expect(historyContents.count == 1)
        let snapshotScene = root
            .appendingPathComponent("History")
            .appendingPathComponent(historyContents[0])
            .appendingPathComponent("Manuscript/01 Scene.md")
        #expect(FileManager.default.fileExists(atPath: snapshotScene.path))
    }

    @Test("a second snapshot is skipped when nothing changed since the last one")
    func skipsUnchangedSnapshot() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        _ = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)
        let secondCreated = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)

        #expect(secondCreated == false)
        let historyContents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("History").path)
        #expect(historyContents.count == 1)
    }

    @Test("a snapshot is taken again once the working tree actually changes")
    func snapshotsAgainAfterAChange() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        _ = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)
        try Data("A different opening line.".utf8).write(to: root.appendingPathComponent("Manuscript/01 Scene.md"))
        let secondCreated = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)

        #expect(secondCreated)
        let historyContents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("History").path)
        #expect(historyContents.count == 2)
    }

    @Test("a snapshot is taken again when a whole top-level entry is deleted, even if nothing else changed")
    func snapshotsAgainAfterATopLevelDeletion() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        let notes = root.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("Some notes.".utf8).write(to: notes.appendingPathComponent("idea.md"))

        _ = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)
        try FileManager.default.removeItem(at: notes)
        let secondCreated = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)

        #expect(secondCreated)
        let historyContents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("History").path)
        #expect(historyContents.count == 2)
    }

    @Test("show/contents reads a file's text back out of a specific snapshot")
    func showsContentsAtASnapshot() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()
        _ = try await service.createSnapshot(trigger: .checkpoint(label: nil), machineName: "M", in: root)

        let entries = try await service.log(for: nil, in: root)
        let contents = try await service.show(path: "Manuscript/01 Scene.md", at: entries[0].sha, in: root)

        #expect(contents == "Once upon a time.")
    }

    @Test("log(for:) only returns entries where that file actually changed")
    func logFiltersToChangedEntries() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        _ = try await service.createSnapshot(trigger: .checkpoint(label: "first"), machineName: "M", in: root)
        // An unrelated file changes; the scene itself doesn't.
        try Data("cover data".utf8).write(to: root.appendingPathComponent("Resources.txt"))
        _ = try await service.createSnapshot(trigger: .checkpoint(label: "unrelated change"), machineName: "M", in: root)
        try Data("A revised opening line.".utf8).write(to: root.appendingPathComponent("Manuscript/01 Scene.md"))
        _ = try await service.createSnapshot(trigger: .checkpoint(label: "scene changed"), machineName: "M", in: root)

        let entries = try await service.log(for: "Manuscript/01 Scene.md", in: root)

        #expect(entries.count == 2)
        #expect(entries[0].subject.contains("scene changed"))
        #expect(entries[1].subject.contains("first"))
    }

    @Test("log(for: nil) returns every snapshot, newest first, for the project-wide Timeline")
    func logWithNoPathReturnsEverySnapshot() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()

        _ = try await service.createSnapshot(trigger: .checkpoint(label: "first"), machineName: "M", in: root)
        try Data("more".utf8).write(to: root.appendingPathComponent("Manuscript/01 Scene.md"))
        _ = try await service.createSnapshot(trigger: .checkpoint(label: "second"), machineName: "M", in: root)

        let entries = try await service.log(for: nil, in: root)

        #expect(entries.map(\.subject).map { $0.contains("second") } == [true, false])
    }

    @Test("pruneSnapshots thins old, unprotected snapshots per SnapshotRetention")
    func prunesOldSnapshots() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()
        let historyDirectory = root.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!
        let ancient = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        for offset in 0..<2 {
            let name = "2026-01-01 00-0\(offset)-00 M"
            let folder = historyDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Explicit, readable, unprotected metadata — the fail-safe for *unreadable*
            // metadata defaults to protected (never prune on uncertainty), so this test
            // needs real metadata to actually exercise pruning of unprotected snapshots.
            let metadata = SnapshotMetadata(subject: "Autosave", isProtectedFromPruning: false)
            try JSONEncoder().encode(metadata).write(to: folder.appendingPathComponent(SnapshotMetadata.filename))
        }

        try await service.pruneSnapshots(in: root, now: now)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: historyDirectory.path)
        #expect(remaining.count == 1)
        _ = ancient
    }

    @Test("pruneSnapshots never removes a snapshot whose metadata can't be read — fails closed, not open")
    func doesNotPruneUnreadableMetadata() async throws {
        let root = try makeWorkingTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SnapshotService()
        let historyDirectory = root.appendingPathComponent("History")

        let name = "2026-01-01 00-00-00 M"
        let folder = historyDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // No .drafter-snapshot.json written at all — readMetadata will throw.

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!

        try await service.pruneSnapshots(in: root, now: now)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: historyDirectory.path)
        #expect(remaining == [name])
    }

    @Test("cloudProvider detects a Box-synced path and returns nil for a plain local path")
    func detectsCloudProvider() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let boxPath = home.appendingPathComponent("Library/CloudStorage/Box-Box/Drafter Backups/My Book")
        let localPath = home.appendingPathComponent("Documents/Drafter/Projects/My Book")

        #expect(SnapshotService.cloudProvider(for: boxPath, homeDirectory: home) == "Box")
        #expect(SnapshotService.cloudProvider(for: localPath, homeDirectory: home) == nil)
    }
}
