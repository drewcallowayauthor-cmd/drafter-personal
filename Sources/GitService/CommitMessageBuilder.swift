import Foundation

/// The commit triggers from §5.4 — every automatic commit maps to exactly one of these.
public enum CommitTrigger: Sendable, Equatable {
    case autosave(filesChanged: Int, wordDelta: Int)
    case focusLost
    case sessionEnd(wordDelta: Int)
    case preExport
    case checkpoint(label: String?)
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

    private static func signed(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        let magnitude = formatter.string(from: NSNumber(value: abs(n))) ?? String(abs(n))
        return n < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
