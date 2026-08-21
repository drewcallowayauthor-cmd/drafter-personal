import DrafterCore
import Foundation
import ProjectStore
import SnapshotService

/// Backs §7.5's conflicted-copy banner (Local-file mode only): scans for a cloud
/// client's own conflict-copy naming next to the file it duplicates, and resolves one
/// by either keeping it (overwriting the original) or discarding it.
@MainActor
@Observable
final class ConflictedCopyViewModel {
    private(set) var matches: [ConflictedCopyDetector.Match] = []
    private(set) var actionErrorMessage: String?

    private let fileWriter: AtomicFileWriting

    init(fileWriter: AtomicFileWriting = LiveAtomicFileWriter()) {
        self.fileWriter = fileWriter
    }

    func scan(workingTree: URL) {
        matches = ConflictedCopyDetector.scan(workingTree: workingTree)
    }

    func clear() {
        matches = []
    }

    /// The two-pane diff for §7.5's "Compare with original" — front-matter-stripped,
    /// matching what the History panel already shows.
    func compareLines(for match: ConflictedCopyDetector.Match) -> [SceneDiffLine]? {
        guard
            let originalData = FileManager.default.contents(atPath: match.originalURL.path),
            let conflictedData = FileManager.default.contents(atPath: match.conflictedURL.path)
        else {
            actionErrorMessage = "Couldn't read one of these files."
            return nil
        }
        let originalBody = SceneFrontMatter.parse(String(decoding: originalData, as: UTF8.self)).body
        let conflictedBody = SceneFrontMatter.parse(String(decoding: conflictedData, as: UTF8.self)).body
        return SceneDiff.diff(old: originalBody, new: conflictedBody)
    }

    /// "Keep this one" — the conflict copy's content wins: written over the original,
    /// then the conflict copy itself is removed so it doesn't linger in the binder.
    func keepConflictedCopy(_ match: ConflictedCopyDetector.Match) {
        do {
            guard let data = FileManager.default.contents(atPath: match.conflictedURL.path) else {
                throw DrafterError.filesystem(underlying: "couldn't read \(match.conflictedURL.path)")
            }
            try fileWriter.write(data, to: match.originalURL)
            try FileManager.default.removeItem(at: match.conflictedURL)
            matches.removeAll { $0 == match }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    /// "Delete" — discards the conflict copy, leaving the original untouched.
    func deleteConflictedCopy(_ match: ConflictedCopyDetector.Match) {
        do {
            try FileManager.default.removeItem(at: match.conflictedURL)
            matches.removeAll { $0 == match }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func clearActionErrorMessage() {
        actionErrorMessage = nil
    }
}
