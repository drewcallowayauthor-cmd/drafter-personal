import DrafterCore
import Foundation
import GitService
import SnapshotService

/// §8.3: no lock file — instead, on project open and on focus, check whether the
/// backing store has activity from a *different* machine within the last 5 minutes.
/// Git mode reads `origin/main`; Local-file mode reads the newest `History/` snapshot.
enum ConcurrentEditingWarning {
    struct Info: Equatable {
        let machineName: String
        let secondsAgo: Int
    }

    /// `nil` if there's no recent activity from elsewhere (including if the fetch or
    /// log itself fails — this is a courtesy heads-up, not a correctness check, so it
    /// fails silently like everything else network-related per §6.5).
    static func check(
        gitService: GitService,
        workingTree: URL,
        ownMachineName: String,
        window: TimeInterval = 300,
        now: Date = .now
    ) async -> Info? {
        let entries: [CommitLogEntry]
        do {
            entries = try await gitService.log(ref: "origin/main", in: workingTree)
        } catch {
            DrafterLog.app.error("Concurrent-editing check failed to read origin/main log: \(error, privacy: .public)")
            return nil
        }
        return recentOther(in: entries, ownMachineName: ownMachineName, window: window, now: now)
    }

    /// Local-file mode's equivalent (§7.7): the newest snapshot is already whatever the
    /// cloud client has synced down locally, so — unlike Git mode — there's no separate
    /// fetch step first.
    static func checkLocalFile(
        snapshotService: SnapshotService,
        workingTree: URL,
        ownMachineName: String,
        window: TimeInterval = 300,
        now: Date = .now
    ) async -> Info? {
        let entries: [CommitLogEntry]
        do {
            entries = try await snapshotService.log(for: nil, in: workingTree)
        } catch {
            DrafterLog.app.error("Concurrent-editing check failed to read the snapshot log: \(error, privacy: .public)")
            return nil
        }
        return recentOther(in: entries, ownMachineName: ownMachineName, window: window, now: now)
    }

    private static func recentOther(
        in entries: [CommitLogEntry],
        ownMachineName: String,
        window: TimeInterval,
        now: Date
    ) -> Info? {
        let cutoff = now.addingTimeInterval(-window)
        guard
            let recent = entries.first(where: {
                !$0.machineName.isEmpty && $0.machineName != ownMachineName && $0.date >= cutoff
            })
        else {
            return nil
        }
        return Info(machineName: recent.machineName, secondsAgo: max(0, Int(now.timeIntervalSince(recent.date))))
    }
}
