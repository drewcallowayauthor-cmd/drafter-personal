import DrafterCore
import Foundation

/// §5.4's commit-trigger debounce — distinct from (and coarser than) §8.3's 2s
/// disk-write autosave. Accumulates word deltas across edits and commits 90s after the
/// last one, coalescing a burst of typing into a single "autosave" commit rather than
/// one per keystroke. Triggers other than the debounced autosave (focus lost, session
/// end, pre-export, checkpoint) bypass the debounce entirely via `flush(trigger:)`.
@MainActor
public final class AutocommitScheduler {
    private let checkpointCoordinator: any CheckpointCoordinating
    private let debounceDelay: Duration

    private var pendingWordDelta = 0
    private var pendingFileCount = 0
    private var debounceTask: Task<Void, Never>?

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
        if (try? await checkpointCoordinator.commit(trigger: trigger)) == true {
            onCommitted?()
        }
    }

    private func flushDebounced() async {
        let wordDelta = pendingWordDelta
        let fileCount = pendingFileCount
        pendingWordDelta = 0
        pendingFileCount = 0
        guard fileCount > 0 else { return }
        if (try? await checkpointCoordinator.commit(trigger: .autosave(filesChanged: fileCount, wordDelta: wordDelta))) == true {
            onCommitted?()
        }
    }
}
