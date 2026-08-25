import Foundation

/// The commit/snapshot triggers from §6.4 — every automatic checkpoint, in either mode,
/// maps to exactly one of these. §7.2: Local-file mode reuses this exact trigger table.
public enum CommitTrigger: Sendable, Equatable {
    case autosave(filesChanged: Int, wordDelta: Int)
    case focusLost
    case sessionEnd(wordDelta: Int)
    case preExport
    case checkpoint(label: String?)

    /// §7.3's retention rule: a checkpoint or pre-export snapshot is never thinned,
    /// since it's the one a writer is most likely to reach for later. Git mode has no
    /// equivalent pruning, so this only matters to `SnapshotService`.
    public var isProtectedFromPruning: Bool {
        switch self {
        case .checkpoint, .preExport: return true
        case .autosave, .focusLost, .sessionEnd: return false
        }
    }
}

/// Drives a checkpoint in whichever mode a project uses — `RepositoryCoordinator`
/// (Git mode, a git commit) or `SnapshotCoordinator` (Local-file mode, a `History/`
/// snapshot). `AutocommitScheduler`'s debounce/trigger logic is shared between both
/// modes (§7.2) by depending on this instead of a concrete coordinator type.
public protocol CheckpointCoordinating: Sendable {
    @discardableResult
    func commit(trigger: CommitTrigger) async throws -> Bool
}

/// Builds commit messages per §5.4's trigger table, with the machine trailer appended
/// so the unified timeline stays legible across devices.
public enum CommitMessageBuilder {
    public static func message(for trigger: CommitTrigger, machine: String) -> String {
        "\(subject(for: trigger))\n\nMachine: \(machine)"
    }

    private static func subject(for trigger: CommitTrigger) -> String {
        switch trigger {
        case .autosave(let filesChanged, let wordDelta):
            let files = filesChanged == 1 ? "file" : "files"
            let words = abs(wordDelta) == 1 ? "word" : "words"
            return "autosave — \(filesChanged) \(files), \(signed(wordDelta)) \(words)"
        case .focusLost:
            return "autosave (focus lost)"
        case .sessionEnd(let wordDelta):
            let words = abs(wordDelta) == 1 ? "word" : "words"
            return "session end — \(signed(wordDelta)) \(words)"
        case .preExport:
            return "pre-export"
        case .checkpoint(let label):
            guard let label, !label.isEmpty else { return "checkpoint" }
            return "checkpoint — \(label)"
        }
    }

    private static func signed(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        let magnitude = formatter.string(from: NSNumber(value: abs(number))) ?? String(abs(number))
        return number < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
