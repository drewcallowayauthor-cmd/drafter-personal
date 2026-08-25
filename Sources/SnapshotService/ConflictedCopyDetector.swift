import DrafterCore
import Foundation

/// §7.5: Local-file mode has no merge engine, so a genuine conflict — the same scene
/// edited on two machines before the cloud client synced — surfaces as whatever that
/// client's own conflict-copy naming convention produces, sitting right there in the
/// binder. This watches for those naming patterns and pairs a suspected conflict copy
/// with the original file it duplicates.
public enum ConflictedCopyDetector {
    public struct Match: Sendable, Equatable, Identifiable {
        public var id: URL { conflictedURL }
        public let conflictedURL: URL
        public let originalURL: URL

        public init(conflictedURL: URL, originalURL: URL) {
            self.conflictedURL = conflictedURL
            self.originalURL = originalURL
        }
    }

    /// Appendix B's watched patterns, tried in order. Each captures the filename it
    /// believes is the "clean" original, extension included. `try!` is safe here — these
    /// are hardcoded, compile-time-constant patterns; a `RegexCompileSafetyTests` unit
    /// test guards against a future edit introducing a typo.
    private static let patterns: [NSRegularExpression] = [
        // Dropbox: "<name> (<user>'s conflicted copy <date>).md"
        // Box:     "<name> (Conflicted copy <date>).md"
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^(.+) \([^()]*[Cc]onflicted copy[^()]*\)(\.[^.]+)$"#),
        // iCloud Drive: "<name> 2.md", "<name> 3.md", …
        try! NSRegularExpression(pattern: #"^(.+) \d+(\.[^.]+)$"#), // swiftlint:disable:this force_try
        // OneDrive: "<name>-<machine>.md"
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^(.+)-[A-Za-z0-9][A-Za-z0-9 ]*(\.[^.]+)$"#)
    ]

    /// The filename this one *looks* like a conflict copy of, per Appendix B's naming
    /// patterns — a guess based on the name alone, not yet confirmed against the
    /// filesystem. `nil` if `filename` doesn't match any known pattern.
    public static func candidateOriginalFilename(for filename: String) -> String? {
        let range = NSRange(filename.startIndex..., in: filename)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: filename, range: range),
                let nameRange = Range(match.range(at: 1), in: filename),
                let extRange = Range(match.range(at: 2), in: filename)
            else { continue }
            return String(filename[nameRange]) + String(filename[extRange])
        }
        return nil
    }

    /// Scans `workingTree` for files matching a conflict-copy pattern whose guessed
    /// original also actually exists alongside it — that second check is what keeps
    /// this from flagging an ordinarily-numbered scene as a false positive: a genuine
    /// conflict copy always sits next to the file it duplicates, and it's this
    /// pairing, not the name alone, that the banner (§7.5) acts on.
    public static func scan(workingTree: URL, fileManager: FileManager = .default) -> [Match] {
        var matches: [Match] = []
        let excludedTopLevelNames: Set<String> = ["History", "Build", "Resources"]
        let topLevelNames: [String]
        do {
            topLevelNames = try fileManager.contentsOfDirectory(atPath: workingTree.path)
        } catch {
            // swiftlint:disable:next line_length
            DrafterLog.snapshot.error("Failed to scan \(workingTree.path, privacy: .public) for conflicted copies: \(error, privacy: .public)")
            topLevelNames = []
        }

        for topLevelName in topLevelNames {
            guard !topLevelName.hasPrefix("."), !excludedTopLevelNames.contains(topLevelName) else { continue }
            let directory = workingTree.appendingPathComponent(topLevelName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard
                let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "md" else { continue }
                guard let originalName = candidateOriginalFilename(for: fileURL.lastPathComponent) else { continue }
                let originalURL = fileURL.deletingLastPathComponent().appendingPathComponent(originalName)
                guard originalURL != fileURL, fileManager.fileExists(atPath: originalURL.path) else { continue }
                matches.append(Match(conflictedURL: fileURL, originalURL: originalURL))
            }
        }
        return matches
    }
}
