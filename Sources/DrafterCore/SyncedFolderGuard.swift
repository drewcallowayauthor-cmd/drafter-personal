import Foundation

/// §12.1's hard block: a `.git` directory inside a cloud-sync client's folder will
/// eventually corrupt (no atomic directory semantics, placeholder eviction, conflict
/// copies written into the object store). Checked on project create and open.
public enum SyncedFolderGuard {
    /// Relative to the user's home directory.
    public static let blockedRelativePaths = [
        "Library/CloudStorage",
        "Dropbox",
        "Google Drive",
        "OneDrive",
        "Library/Mobile Documents"
    ]

    /// Returns `.locationInsideSyncedFolder` if `url` resolves to a path under one of
    /// the blocked directories, `nil` otherwise. Resolves symlinks first, since Box
    /// Drive and friends are frequently reached through one.
    public static func check(_ url: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> DrafterError? {
        let resolvedPath = url.resolvingSymlinksInPath().path
        let home = homeDirectory.resolvingSymlinksInPath().path
        for relativePath in blockedRelativePaths {
            let blockedPath = (home as NSString).appendingPathComponent(relativePath)
            if resolvedPath == blockedPath || resolvedPath.hasPrefix(blockedPath + "/") {
                return .locationInsideSyncedFolder(path: resolvedPath)
            }
        }
        return nil
    }
}
