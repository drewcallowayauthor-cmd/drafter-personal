import DrafterCore
import Foundation

/// Sidecar written into every snapshot folder, alongside the copied `Manuscript/` etc.
/// A git commit carries its own message; a plain folder copy has nowhere to put one, so
/// this is that — just enough to reconstruct the same `subject` text
/// `CommitMessageBuilder` would have produced, so §7.4's History rows read identically
/// in both modes. Date and machine aren't duplicated here — they're already encoded in
/// the folder name (`SnapshotFolderName`).
struct SnapshotMetadata: Codable, Sendable, Equatable {
    let subject: String
    let isProtectedFromPruning: Bool

    static let filename = ".drafter-snapshot.json"

    static func make(trigger: CommitTrigger, machine: String) -> SnapshotMetadata {
        // `CommitMessageBuilder` appends "\n\nMachine: <name>" — irrelevant here since
        // the folder name already carries the machine, so just the first line is kept.
        let message = CommitMessageBuilder.message(for: trigger, machine: machine)
        let subject = message.components(separatedBy: "\n\n").first ?? message
        return SnapshotMetadata(subject: subject, isProtectedFromPruning: trigger.isProtectedFromPruning)
    }
}
