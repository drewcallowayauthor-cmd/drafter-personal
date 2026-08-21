import Foundation
import GitService
import ProjectStore
import SnapshotService

/// Settings is its own `Scene` (`Settings { SettingsView() }`), so it has no direct
/// reference to `ContentView`'s `ProjectViewModel` and the git/snapshot wiring for
/// whichever project is currently open. This singleton bridges that gap for the
/// Version Control and Versioning panes' project-scoped actions — `ProjectViewModel`
/// updates it on attach/close, mirroring how it already updates `OpenProjectRegistry`.
/// `OpenProjectRegistry` itself isn't reused here: it only tracks open root *paths* to
/// block double-opening, and holds no coordinator references.
@MainActor
@Observable
public final class OpenProjectHandle {
    public static let shared = OpenProjectHandle()

    public private(set) var workingTreeRoot: URL?
    public private(set) var versionControlMode: VersionControlMode?
    private var gitService: GitService?
    private var snapshotService: SnapshotService?

    private init() {}

    public func setGit(workingTreeRoot: URL, gitService: GitService) {
        self.workingTreeRoot = workingTreeRoot
        self.versionControlMode = .git
        self.gitService = gitService
        self.snapshotService = nil
    }

    public func setLocalFile(workingTreeRoot: URL, snapshotService: SnapshotService) {
        self.workingTreeRoot = workingTreeRoot
        self.versionControlMode = .localFile
        self.snapshotService = snapshotService
        self.gitService = nil
    }

    public func clear() {
        workingTreeRoot = nil
        versionControlMode = nil
        gitService = nil
        snapshotService = nil
    }

    /// Git mode's `origin` remote URL, for the Version Control pane's display-only row.
    /// `nil` for a local-only project (no remote configured) as well as for Local-file
    /// mode.
    public func remoteURLDescription() async throws -> String? {
        guard let workingTreeRoot, versionControlMode == .git else { return nil }
        return try await gitService?.remoteURL(in: workingTreeRoot)
    }

    /// Git: `git count-objects -vH`. Local-file: total size of `History/` on disk.
    public func historySizeDescription() async throws -> String? {
        guard let workingTreeRoot else { return nil }
        switch versionControlMode {
        case .git:
            return try await gitService?.repositorySize(workingTree: workingTreeRoot)
        case .localFile:
            let historyURL = workingTreeRoot.appendingPathComponent("History")
            return Self.directorySizeDescription(at: historyURL)
        case nil:
            return nil
        }
    }

    /// Git: `git gc`. Local-file: retention pruning (§7.3), otherwise only run
    /// automatically on project close.
    public func runMaintenance() async throws {
        guard let workingTreeRoot else { return }
        switch versionControlMode {
        case .git:
            try await gitService?.runMaintenance(workingTree: workingTreeRoot)
        case .localFile:
            try await SnapshotCoordinator(
                snapshotService: snapshotService ?? SnapshotService(),
                workingTree: workingTreeRoot
            ).pruneSnapshots()
        case nil:
            break
        }
    }

    /// Local-file mode's manual "Snapshot Now" (§12) — Git mode has no equivalent
    /// action since its commits already happen on the usual debounced triggers.
    public func snapshotNow() async throws {
        guard let workingTreeRoot, versionControlMode == .localFile else { return }
        _ = try await (snapshotService ?? SnapshotService()).createSnapshot(
            trigger: .checkpoint(label: "manual snapshot"),
            machineName: RepositoryCoordinator.defaultMachineName(),
            in: workingTreeRoot
        )
    }

    private static func directorySizeDescription(at url: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalBytes += Int64(values?.fileSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
