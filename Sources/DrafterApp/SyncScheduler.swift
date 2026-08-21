import DrafterCore
import Foundation
import GitService
import Observation

/// §5.5's sync loop, in terms of `GitService.SyncCoordinator.syncNow()`: an immediate
/// pass on `start()`, a periodic pass every `fetchInterval`, a debounced pass ~30s
/// after any commit, and a final pass on `syncBeforeClose()`. Publishes `state` for the
/// toolbar's sync status control.
@MainActor
@Observable
final class SyncScheduler {
    private(set) var state: SyncState = .idle

    private let syncCoordinator: SyncCoordinator
    private let fetchInterval: Duration
    private let pushDebounceDelay: Duration

    private var periodicTask: Task<Void, Never>?
    private var pushDebounceTask: Task<Void, Never>?

    init(syncCoordinator: SyncCoordinator, fetchInterval: Duration = .seconds(180), pushDebounceDelay: Duration = .seconds(30)) {
        self.syncCoordinator = syncCoordinator
        self.fetchInterval = fetchInterval
        self.pushDebounceDelay = pushDebounceDelay
    }

    /// Project open (§5.5's "Project open: fetch, then integrate"). Runs one pass
    /// immediately, then keeps syncing every `fetchInterval` until `stop()`.
    func start() {
        Task { await syncNow() }
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.fetchInterval)
                guard !Task.isCancelled else { return }
                await self.syncNow()
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
    }

    /// "Window regains focus" (§5.5).
    func syncOnFocusRegained() {
        Task { await syncNow() }
    }

    /// "~30s after any commit (debounced): push" (§5.5) — routed through the same
    /// `syncNow()` as everything else, since a bare push isn't a legal state
    /// transition without a fetch first (see `SyncCoordinator`'s doc comment).
    func schedulePushAfterCommit() {
        pushDebounceTask?.cancel()
        let delay = pushDebounceDelay
        pushDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// "Project close: commit, integrate, push, wait for completion" (§5.5). The
    /// commit itself is `AutocommitScheduler.flush`'s job (it owns the working tree's
    /// dirty state); this covers the integrate-push-and-wait half.
    func syncBeforeClose() async {
        pushDebounceTask?.cancel()
        await syncNow()
    }

    /// Call after §5.7's conflict sheet has resolved and pushed every conflicted
    /// path — clears `.conflicted` in the underlying `SyncCoordinator` and runs one
    /// more pass so `state` reflects reality again.
    func resolveConflict() async {
        if let newState = try? await syncCoordinator.markConflictResolved() {
            state = newState
        }
        await syncNow()
    }

    private func syncNow() async {
        if let newState = try? await syncCoordinator.syncNow() {
            state = newState
        }
    }
}
