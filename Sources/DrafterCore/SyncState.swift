import Foundation

/// The sync status machine described in §7: modeled explicitly, rather than as scattered
/// booleans, because it's the part of the app most likely to become spaghetti.
public enum SyncState: Sendable, Equatable {
    case idle
    case fetching
    case merging
    case conflicted(paths: [String])
    case pushing
    case offline(pendingCommits: Int)

    /// Whether `next` is a legal transition from `self`.
    ///
    /// `.conflicted` is terminal until the user resolves it (§5.7) — every state
    /// transitions to `.conflicted`, but the only way out is `.resolving`, which
    /// callers represent by transitioning to `.merging` once resolution is committed.
    public func canTransition(to next: SyncState) -> Bool {
        switch (self, next) {
        case (.conflicted, .idle), (.conflicted, .merging):
            return true
        case (.conflicted, _):
            return false
        case (_, .conflicted):
            return true
        case (.idle, .fetching), (.idle, .offline):
            return true
        case (.fetching, .merging), (.fetching, .pushing), (.fetching, .idle), (.fetching, .offline):
            return true
        case (.merging, .pushing), (.merging, .idle), (.merging, .offline):
            return true
        case (.pushing, .idle), (.pushing, .offline):
            return true
        case (.offline, .fetching), (.offline, .offline), (.offline, .idle):
            return true
        default:
            return false
        }
    }
}

public enum SyncStateError: Error, Sendable, Equatable {
    case illegalTransition(from: SyncState, to: SyncState)
}

/// Owns the current `SyncState` and enforces legal transitions.
public actor SyncStateMachine {
    public private(set) var state: SyncState

    public init(initial: SyncState = .idle) {
        self.state = initial
    }

    @discardableResult
    public func transition(to next: SyncState) throws -> SyncState {
        guard state.canTransition(to: next) else {
            throw SyncStateError.illegalTransition(from: state, to: next)
        }
        state = next
        return state
    }
}
