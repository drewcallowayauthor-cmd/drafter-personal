import Foundation

/// The classification from §5.6, decided purely from ahead/behind counts. Whether a
/// `.merge` resolves cleanly or lands in `.conflicted` (§5.7) can only be known after
/// actually running the merge — that's a separate step layered on top of this decision.
public enum IntegrationDecision: Sendable, Equatable {
    case identical
    case fastForward
    case push
    case merge
}

public enum IntegrationStrategy {
    public static func decide(ahead: Int, behind: Int) -> IntegrationDecision {
        switch (ahead, behind) {
        case (0, 0): return .identical
        case (0, _): return .fastForward
        case (_, 0): return .push
        default: return .merge
        }
    }
}
