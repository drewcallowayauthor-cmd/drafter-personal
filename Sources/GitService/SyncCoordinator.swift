import DrafterCore
import Foundation

/// Orchestrates §5.5's sync loop and §5.6's integration strategy: fetch, classify how
/// local `HEAD` relates to the remote, then fast-forward / push / merge as appropriate —
/// driving `SyncStateMachine` through the states described in §7. Timers and debouncing
/// (§5.5's "every 3 minutes", "~30s after any commit") are the app layer's job; this
/// just runs one integration pass per call to `syncNow()`. Every push happens as the
/// tail of a `syncNow()` pass, never standalone — the state machine only allows
/// `.pushing` to follow `.fetching` or `.merging`, so an isolated "just push" step from
/// `.idle` isn't legal, matching §5.5's intent that a push always follows a fresh fetch.
public actor SyncCoordinator {
    private let gitService: GitService
    private let stateMachine: SyncStateMachine
    private let workingTree: URL
    private let machineName: String
    private let remote: String
    private let branch: String

    /// Ahead-count from the last successful `divergence` check, used as the
    /// `pendingCommits` figure when a subsequent network step fails and the state
    /// machine falls into `.offline` (§5.5's status indicator: "Offline — 4 commits
    /// pending").
    private var lastKnownAheadCount = 0

    public init(
        gitService: GitService,
        workingTree: URL,
        machineName: String,
        remote: String = "origin",
        branch: String = "main",
        stateMachine: SyncStateMachine = SyncStateMachine()
    ) {
        self.gitService = gitService
        self.workingTree = workingTree
        self.machineName = machineName
        self.remote = remote
        self.branch = branch
        self.stateMachine = stateMachine
    }

    public var state: SyncState {
        get async { await stateMachine.state }
    }

    private var remoteRef: String { "\(remote)/\(branch)" }

    /// One pass of §5.6. Network failures (fetch, a rejected push) resolve to
    /// `.offline` rather than throwing — §5.5 treats being offline as normal, not an
    /// error, so callers don't need a catch block on every timer tick. A merge that
    /// conflicts resolves to `.conflicted` and stops; §5.7's resolution flow is the only
    /// way out, so a `.conflicted` state short-circuits future calls until then.
    @discardableResult
    public func syncNow() async throws -> SyncState {
        if case .conflicted = await stateMachine.state {
            return await stateMachine.state
        }

        try await transition(to: .fetching)
        do {
            try await gitService.fetch(remote: remote, in: workingTree)
        } catch {
            return try await transition(to: failureState(for: error))
        }

        // A brand-new GitHub repo has no branches at all until the first push
        // succeeds (§5.2) — `divergence` can't compare against a ref that doesn't
        // exist yet, so treat "no such branch on the remote" the same as "local
        // ahead": just push and let that create it. This also self-heals a project
        // whose initial connection got as far as `addRemote` but never completed the
        // push (e.g. an auth failure mid-connection).
        let remoteBranchExists = (try? await gitService.refExists(remoteRef, in: workingTree)) ?? false
        guard remoteBranchExists else {
            return try await push()
        }

        let divergence: (ahead: Int, behind: Int)
        do {
            divergence = try await gitService.divergence(from: remoteRef, in: workingTree)
        } catch {
            return try await transition(to: .offline(pendingCommits: lastKnownAheadCount))
        }
        lastKnownAheadCount = divergence.ahead

        switch (divergence.ahead, divergence.behind) {
        case (0, 0):
            return try await transition(to: .idle)

        case (0, let behind) where behind > 0:
            try await transition(to: .merging)
            do {
                try await gitService.fastForwardMerge(to: remoteRef, in: workingTree)
            } catch {
                return try await transition(to: .offline(pendingCommits: lastKnownAheadCount))
            }
            return try await transition(to: .idle)

        case (let ahead, 0) where ahead > 0:
            return try await push()

        default:
            try await transition(to: .merging)
            let result: MergeResult
            do {
                result = try await gitService.merge(
                    with: remoteRef,
                    message: "merge from \(machineName)",
                    in: workingTree
                )
            } catch {
                return try await transition(to: .offline(pendingCommits: lastKnownAheadCount))
            }
            switch result {
            case .clean:
                return try await push()
            case .conflicted(let paths):
                return try await transition(to: .conflicted(paths: paths))
            }
        }
    }

    /// Call once §5.7's `ConflictResolver.finalize` has committed and pushed every
    /// conflicted path — `ConflictResolver` operates via raw `GitService` calls and
    /// doesn't touch this actor's state machine, so without this, `.conflicted` would
    /// stay terminal forever even after the conflict is actually resolved on disk.
    @discardableResult
    public func markConflictResolved() async throws -> SyncState {
        try await transition(to: .idle)
    }

    /// Must be called with the state machine already in `.fetching` or `.merging` —
    /// both `syncNow()` branches that reach here satisfy that, and it's the only way
    /// `.pushing` is a legal next state. Always sets upstream tracking (`-u`) rather
    /// than a plain push — harmless when it's already set, and necessary the first
    /// time a branch is pushed to a remote that didn't have it yet.
    private func push() async throws -> SyncState {
        try await transition(to: .pushing)
        do {
            try await gitService.pushSettingUpstream(remote: remote, branch: branch, in: workingTree)
        } catch {
            if isAuthenticationFailure(error) {
                return try await transition(to: .authenticationRequired)
            }
            return try await transition(to: .offline(pendingCommits: max(lastKnownAheadCount, 1)))
        }
        lastKnownAheadCount = 0
        return try await transition(to: .idle)
    }

    /// §12.2 point 4: a rejected token should read as "reconnect in Settings," not as
    /// a generic connectivity blip. Git's CLI has no structured way to report this —
    /// a bad PAT surfaces as a non-zero exit with GitHub's own wording on stderr — so
    /// this matches the phrases GitHub's smart-HTTP backend actually uses.
    private func failureState(for error: Error) -> SyncState {
        isAuthenticationFailure(error)
            ? .authenticationRequired
            : .offline(pendingCommits: lastKnownAheadCount)
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        guard case DrafterError.processFailed(_, _, let stderr) = error else { return false }
        let lowered = stderr.lowercased()
        return lowered.contains("authentication failed")
            || lowered.contains("invalid credentials")
            || lowered.contains("access denied")
            || lowered.contains("403")
    }

    @discardableResult
    private func transition(to next: SyncState) async throws -> SyncState {
        try await stateMachine.transition(to: next)
    }
}
