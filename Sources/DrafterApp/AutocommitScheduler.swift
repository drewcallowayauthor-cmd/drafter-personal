import DrafterCore
import Foundation
import Observation

/// §5.4's commit-trigger debounce — distinct from (and coarser than) §8.3's 2s
/// disk-write autosave. Accumulates word deltas across edits and commits 90s after the
/// last one, coalescing a burst of typing into a single "autosave" commit rather than
/// one per keystroke. Triggers other than the debounced autosave (focus lost, session
/// end, pre-export, checkpoint) bypass the debounce entirely via `flush(trigger:)`.
@MainActor
@Observable
public final class AutocommitScheduler {
    private let checkpointCoordinator: any CheckpointCoordinating
    /// `var`, not `let`: re-read on every `recordActivity` call so a Settings change
    /// to the debounce interval takes effect on an already-open project rather than
    /// only on the next one opened.
    public var debounceDelay: Duration

    private var pendingWordDelta = 0
    private var pendingFileCount = 0
    private var debounceTask: Task<Void, Never>?

    /// Set when the most recent commit attempt (debounced or flushed) threw, cleared
    /// on the next one that succeeds — a quiet signal for the toolbar's save-status
    /// indicator, not an alert: autocommit runs constantly in the background, and a
    /// transient failure here isn't something every tick should interrupt the user
    /// over. Logged in full via `DrafterLog.app` regardless.
    public private(set) var lastCommitFailed = false

    /// Notified after any trigger actually produces a commit — §5.5's "~30s after any
    /// commit: push" hook. `SyncScheduler.schedulePushAfterCommit` is the intended
    /// listener; kept as a closure rather than a direct dependency so this type
    /// doesn't need to know sync exists.
    public var onCommitted: (() -> Void)?

    public init(checkpointCoordinator: any CheckpointCoordinating, debounceDelay: Duration = .seconds(90)) {
        self.checkpointCoordinator = checkpointCoordinator
        self.debounceDelay = debounceDelay
    }

    /// Call after every successful disk save (§8.3's autosave already wrote the file;
    /// this just tracks that a commit is now owed and restarts the 90s debounce).
    public func recordActivity(wordDelta: Int) {
        pendingWordDelta += wordDelta
        pendingFileCount = 1 // only one scene can be open/edited at a time today.

        debounceTask?.cancel()
        let delay = debounceDelay
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flushDebounced()
        }
    }

    /// Commits immediately for a non-debounced trigger (§5.4: focus lost, session end,
    /// pre-export, checkpoint), first canceling any pending debounced autosave so the
    /// same edits aren't committed twice.
    public func flush(trigger: CommitTrigger) async {
        debounceTask?.cancel()
        pendingWordDelta = 0
        pendingFileCount = 0
        if await commit(trigger: trigger) {
            onCommitted?()
        }
    }

    private func flushDebounced() async {
        let wordDelta = pendingWordDelta
        let fileCount = pendingFileCount
        pendingWordDelta = 0
        pendingFileCount = 0
        guard fileCount > 0 else { return }
        if await commit(trigger: .autosave(filesChanged: fileCount, wordDelta: wordDelta)) {
            onCommitted?()
        }
    }

    private func commit(trigger: CommitTrigger) async -> Bool {
        do {
            let committed = try await checkpointCoordinator.commit(trigger: trigger)
            lastCommitFailed = false
            return committed
        } catch {
            DrafterLog.app.error("Autocommit failed: \(error, privacy: .public)")
            lastCommitFailed = true
            return false
        }
    }
}
