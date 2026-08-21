import DrafterCore
import Foundation

/// Local-file mode's version control (§7): whole-project timestamped copies under
/// `History/`, with no `.git`, no remote, and no merge engine — cross-machine movement
/// is left entirely to whatever cloud-sync client the writer already points at the
/// project folder. One instance per open project; like `GitService`, an actor so
/// snapshot creation and pruning for a given working tree never run concurrently with
/// themselves.
public actor SnapshotService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Top-level entries copied into a snapshot — everything a git-mode project would
    /// commit, minus `History/` itself (§4.2's Local-file layout has no `.git`/
    /// `.gitignore`/`.gitattributes` to exclude in the first place).
    private static let excludedTopLevelNames: Set<String> = ["History", "Build"]

    public func historyDirectory(in workingTree: URL) -> URL {
        workingTree.appendingPathComponent("History")
    }

    /// §7.2's snapshot trigger — same trigger table as Git-mode commits (§6.4). Skips
    /// entirely (returns `false`) when nothing has changed since the last snapshot,
    /// mirroring §6.4's "skip when `git status --porcelain` is empty."
    @discardableResult
    public func createSnapshot(trigger: CommitTrigger, machineName: String, in workingTree: URL) async throws -> Bool {
        let existing = try snapshotFolderNames(in: workingTree)
        if let latest = existing.first, try !hasChanged(since: latest, in: workingTree) {
            return false
        }

        let historyDirectory = historyDirectory(in: workingTree)
        try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        // Two snapshots within the same second (e.g. a checkpoint immediately after an
        // autosave) would otherwise collide, since the folder name's precision is
        // whole seconds (Appendix B) — nudge forward a second at a time rather than
        // losing one. Doesn't disturb sort order: the nudged snapshot is still newer
        // than the one it collided with.
        var candidateDate = Date.now
        var folderName = SnapshotFolderName.make(date: candidateDate, machine: machineName)
        while fileManager.fileExists(atPath: historyDirectory.appendingPathComponent(folderName).path) {
            candidateDate = candidateDate.addingTimeInterval(1)
            folderName = SnapshotFolderName.make(date: candidateDate, machine: machineName)
        }
        let destination = historyDirectory.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for name in try topLevelNamesToSnapshot(in: workingTree) {
            // `FileManager.copyItem` uses `copyfile(3)` under the hood, which clones
            // rather than duplicates on an APFS volume (§7.2/Appendix B) — an unchanged
            // Resources/cover.jpg costs no extra disk space until it diverges.
            try fileManager.copyItem(
                at: workingTree.appendingPathComponent(name),
                to: destination.appendingPathComponent(name)
            )
        }

        let metadata = SnapshotMetadata.make(trigger: trigger, machine: machineName)
        try JSONEncoder().encode(metadata).write(to: destination.appendingPathComponent(SnapshotMetadata.filename))

        return true
    }

    /// §7.3 — thins `History/` in place. Call on project close, same as `git gc --auto`.
    public func pruneSnapshots(in workingTree: URL, now: Date = .now) async throws {
        let historyDirectory = historyDirectory(in: workingTree)
        let entries = try snapshotFolderNames(in: workingTree).compactMap { name -> SnapshotRetention.Entry? in
            guard let parsed = SnapshotFolderName.parse(name) else { return nil }
            let metadata: SnapshotMetadata?
            do {
                metadata = try readMetadata(folderName: name, in: workingTree)
            } catch {
                DrafterLog.snapshot.error("Failed to read metadata for snapshot \(name, privacy: .public): \(error, privacy: .public)")
                metadata = nil
            }
            return SnapshotRetention.Entry(
                name: name,
                date: parsed.date,
                isProtected: metadata?.isProtectedFromPruning ?? false
            )
        }
        for name in SnapshotRetention.namesToPrune(entries: entries, now: now) {
            do {
                try fileManager.removeItem(at: historyDirectory.appendingPathComponent(name))
            } catch {
                DrafterLog.snapshot.error("Failed to prune snapshot \(name, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    /// §7.6's provider detection — display-only, never touches a provider API.
    public nonisolated static func cloudProvider(for url: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let resolvedPath = url.resolvingSymlinksInPath().path
        let home = homeDirectory.resolvingSymlinksInPath().path
        let cloudStorage = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if resolvedPath.hasPrefix(cloudStorage + "/") {
            let remainder = resolvedPath.dropFirst(cloudStorage.count + 1)
            let providerFolder = remainder.split(separator: "/").first.map(String.init) ?? ""
            if let dashIndex = providerFolder.firstIndex(of: "-") {
                return String(providerFolder[providerFolder.startIndex..<dashIndex])
            }
            return providerFolder.isEmpty ? nil : providerFolder
        }
        let named: [(String, String)] = [
            ("Dropbox", "Dropbox"),
            ("Library/Mobile Documents", "iCloud Drive")
        ]
        for (relativePath, label) in named {
            let path = (home as NSString).appendingPathComponent(relativePath)
            if resolvedPath == path || resolvedPath.hasPrefix(path + "/") {
                return label
            }
        }
        return nil
    }

    // MARK: - Reading contents at a snapshot

    /// A file's contents within one snapshot — the Local-file equivalent of `git show
    /// <sha>:<path>` (§7.4).
    public func contents(of relativePath: String, at folderName: String, in workingTree: URL) throws -> String {
        let fileURL = historyDirectory(in: workingTree)
            .appendingPathComponent(folderName)
            .appendingPathComponent(relativePath)
        guard let data = fileManager.contents(atPath: fileURL.path) else {
            throw DrafterError.filesystem(underlying: "no snapshot \(folderName) contains \(relativePath)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Internal

    private func topLevelNamesToSnapshot(in workingTree: URL) throws -> [String] {
        let names = try fileManager.contentsOfDirectory(atPath: workingTree.path)
        return names.filter { !$0.hasPrefix(".") && !Self.excludedTopLevelNames.contains($0) }
    }

    private func snapshotFolderNames(in workingTree: URL) throws -> [String] {
        let historyDirectory = historyDirectory(in: workingTree)
        guard fileManager.fileExists(atPath: historyDirectory.path) else { return [] }
        let names = try fileManager.contentsOfDirectory(atPath: historyDirectory.path)
        return names
            .compactMap { name -> (String, Date)? in SnapshotFolderName.parse(name).map { (name, $0.date) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func readMetadata(folderName: String, in workingTree: URL) throws -> SnapshotMetadata {
        let url = historyDirectory(in: workingTree)
            .appendingPathComponent(folderName)
            .appendingPathComponent(SnapshotMetadata.filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SnapshotMetadata.self, from: data)
    }

    /// Compares every snapshotted top-level entry against its copy in the most recent
    /// snapshot — `false` (no change) only if every one is byte-identical.
    /// `FileManager.contentsEqual` recurses through directories on its own.
    private func hasChanged(since folderName: String, in workingTree: URL) throws -> Bool {
        let previous = historyDirectory(in: workingTree).appendingPathComponent(folderName)
        for name in try topLevelNamesToSnapshot(in: workingTree) {
            let current = workingTree.appendingPathComponent(name).path
            let priorCopy = previous.appendingPathComponent(name).path
            guard fileManager.fileExists(atPath: priorCopy) else { return true }
            if !fileManager.contentsEqual(atPath: current, andPath: priorCopy) { return true }
        }
        return false
    }
}

/// §9.1's shared History UI — `HistoryViewModel` drives `SnapshotService` through the
/// exact same interface it drives `GitService` through.
extension SnapshotService: VersioningSource {
    /// `path == nil` is the project-wide Timeline (§7.4); with a path, only entries
    /// where that file actually changed relative to the previous kept snapshot are
    /// returned — the Local-file equivalent of `git log --follow` for a single file,
    /// path-matched rather than id-matched (a scene rename starts a new history trail
    /// here, unlike Git mode's `--follow`).
    public func log(for path: String?, in workingTree: URL) async throws -> [CommitLogEntry] {
        let folderNames = try snapshotFolderNames(in: workingTree) // newest first

        guard let path else {
            // Project-wide Timeline (§7.4): every snapshot, unfiltered.
            return folderNames.compactMap { entry(for: $0, in: workingTree) }
        }

        // Oldest-first pass so "changed relative to the previous (older) snapshot"
        // reads the same direction git log --follow does, then reversed back to
        // newest-first to match. A snapshot's first appearance of the file (no older
        // content to compare against) always counts as a change.
        var results: [CommitLogEntry] = []
        var previousOlderContents: String?
        for folderName in folderNames.reversed() {
            let currentContents = try? contents(of: path, at: folderName, in: workingTree)
            defer { previousOlderContents = currentContents }
            guard let currentContents, currentContents != previousOlderContents else { continue }
            if let entry = entry(for: folderName, in: workingTree) {
                results.append(entry)
            }
        }
        return results.reversed()
    }

    public func show(path: String, at id: String, in workingTree: URL) async throws -> String {
        try contents(of: path, at: id, in: workingTree)
    }

    private func entry(for folderName: String, in workingTree: URL) -> CommitLogEntry? {
        guard let parsed = SnapshotFolderName.parse(folderName) else { return nil }
        let metadata: SnapshotMetadata
        do {
            metadata = try readMetadata(folderName: folderName, in: workingTree)
        } catch {
            DrafterLog.snapshot.error("Failed to read metadata for snapshot \(folderName, privacy: .public): \(error, privacy: .public)")
            metadata = SnapshotMetadata(subject: "snapshot", isProtectedFromPruning: false)
        }
        return CommitLogEntry(
            sha: folderName,
            date: parsed.date,
            subject: metadata.subject,
            authorName: parsed.machine,
            machineName: parsed.machine
        )
    }
}
