import DrafterCore
import Foundation
import ProjectStore

/// Backs §6.8/§7.4's History panel: entries touching the open scene, and restoring an
/// older version as a sibling copy (never an in-place overwrite from this view). Driven
/// through `VersioningSource` (§9.1) rather than `GitService` directly, so the exact
/// same view model and panel work for both Git mode and Local-file mode.
@MainActor
@Observable
final class HistoryViewModel {
    private(set) var entries: [CommitLogEntry] = []
    private(set) var errorMessage: String?
    /// True for the span of `load()` — lets the panel distinguish "genuinely no
    /// history" from "haven't heard back yet" so switching scenes doesn't flash the
    /// empty state while the new scene's entries are still in flight.
    private(set) var isLoading = false
    /// Separate from `errorMessage` on purpose: a failed diff or restore shouldn't
    /// blank out an already-successfully-loaded History list behind an error screen.
    private(set) var actionErrorMessage: String?
    private(set) var isRestoring = false
    /// Set right after a successful restore so the UI can point the writer at the new
    /// file; cleared by the caller once it's handled.
    private(set) var restoredFileURL: URL?

    private let source: any VersioningSource
    private let fileWriter: AtomicFileWriting

    init(source: any VersioningSource, fileWriter: AtomicFileWriting = LiveAtomicFileWriter()) {
        self.source = source
        self.fileWriter = fileWriter
    }

    func load(sceneURL: URL, workingTree: URL) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        // Cleared immediately, before the await below, not just on failure: leaving
        // the previous scene's entries on screen during the async gap let a click land
        // on a stale row, pairing an old entry's id with the new scene's path — the
        // exact shape of "path exists on disk, but not in <id>" from `show`.
        entries = []
        do {
            entries = try await source.log(for: Self.relativePath(of: sceneURL, in: workingTree), in: workingTree)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Restore as copy" (§5.8) — writes the file's contents at `entry` alongside the
    /// current one as `<name> (restored <date>).md`, rather than overwriting anything.
    func restoreAsCopy(entry: CommitLogEntry, sceneURL: URL, workingTree: URL) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let relativePath = Self.relativePath(of: sceneURL, in: workingTree)
            let contents = try await source.show(path: relativePath, at: entry.sha, in: workingTree)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStamp = formatter.string(from: entry.date)

            let baseName = sceneURL.deletingPathExtension().lastPathComponent
            let restoredURL = sceneURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(baseName) (restored \(dateStamp)).md")

            try fileWriter.write(Data(contents.utf8), to: restoredURL)
            restoredFileURL = restoredURL
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func clearRestoredFileURL() {
        restoredFileURL = nil
    }

    func clearActionErrorMessage() {
        actionErrorMessage = nil
    }

    /// The diff for §5.8's two-pane view: `entry`'s version of this scene against
    /// `currentBody` (the live in-editor text, which may itself be unsaved). Both sides
    /// are compared front-matter-stripped, matching what's actually shown in the editor.
    func diffLines(against entry: CommitLogEntry, sceneURL: URL, workingTree: URL, currentBody: String) async -> [SceneDiffLine]? {
        do {
            let relativePath = Self.relativePath(of: sceneURL, in: workingTree)
            let rawOldContents = try await source.show(path: relativePath, at: entry.sha, in: workingTree)
            let oldBody = SceneFrontMatter.parse(rawOldContents).body
            return SceneDiff.diff(old: oldBody, new: currentBody)
        } catch {
            actionErrorMessage = error.localizedDescription
            return nil
        }
    }

    static func relativePath(of fileURL: URL, in workingTree: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = workingTree.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let relative = filePath.dropFirst(rootPath.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }
}
