import DrafterCore
import Foundation
import GitService

/// Backs §5.8's History panel: commits touching the open scene, and restoring an older
/// version as a sibling copy (never an in-place overwrite from this view).
@MainActor
@Observable
final class HistoryViewModel {
    private(set) var entries: [CommitLogEntry] = []
    private(set) var errorMessage: String?
    private(set) var isRestoring = false
    /// Set right after a successful restore so the UI can point the writer at the new
    /// file; cleared by the caller once it's handled.
    private(set) var restoredFileURL: URL?

    private let gitService: GitService
    private let fileWriter: AtomicFileWriting

    init(gitService: GitService, fileWriter: AtomicFileWriting = LiveAtomicFileWriter()) {
        self.gitService = gitService
        self.fileWriter = fileWriter
    }

    func load(sceneURL: URL, workingTree: URL) async {
        errorMessage = nil
        do {
            entries = try await gitService.log(for: Self.relativePath(of: sceneURL, in: workingTree), in: workingTree)
        } catch {
            entries = []
            errorMessage = String(describing: error)
        }
    }

    /// "Restore as copy" (§5.8) — writes the file's contents at `entry` alongside the
    /// current one as `<name> (restored <date>).md`, rather than overwriting anything.
    func restoreAsCopy(entry: CommitLogEntry, sceneURL: URL, workingTree: URL) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let relativePath = Self.relativePath(of: sceneURL, in: workingTree)
            let contents = try await gitService.show(path: relativePath, at: entry.sha, in: workingTree)

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
            errorMessage = String(describing: error)
        }
    }

    func clearRestoredFileURL() {
        restoredFileURL = nil
    }

    static func relativePath(of fileURL: URL, in workingTree: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = workingTree.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let relative = filePath.dropFirst(rootPath.count)
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
    }
}
