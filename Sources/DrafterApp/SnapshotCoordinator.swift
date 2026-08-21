import DrafterCore
import Foundation
import SnapshotService

/// Local-file mode's counterpart to `RepositoryCoordinator` (§7): owns a project's
/// relationship with `SnapshotService` so the rest of the app just calls
/// `commit(trigger:)`, same as Git mode, and doesn't think about `History/` layout,
/// change detection, or retention.
public actor SnapshotCoordinator: CheckpointCoordinating {
    private let snapshotService: SnapshotService
    private let workingTree: URL
    private let machineName: String

    public init(
        snapshotService: SnapshotService,
        workingTree: URL,
        machineName: String = RepositoryCoordinator.defaultMachineName()
    ) {
        self.snapshotService = snapshotService
        self.workingTree = workingTree
        self.machineName = machineName
    }

    @discardableResult
    public func commit(trigger: CommitTrigger) async throws -> Bool {
        try await snapshotService.createSnapshot(trigger: trigger, machineName: machineName, in: workingTree)
    }

    /// §7.3, called on project close — mirrors Git mode's `git gc --auto`.
    public func pruneSnapshots() async throws {
        try await snapshotService.pruneSnapshots(in: workingTree)
    }
}
