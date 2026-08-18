import Foundation

/// The app-wide error taxonomy. Every user-facing failure should resolve to one of these
/// cases rather than a bare `Error`, so the UI can react to the failure category
/// (retry, prompt for re-auth, show a conflict sheet, …) instead of pattern-matching strings.
public enum DrafterError: Error, Sendable, Equatable {
    /// A subprocess (`git`, `pandoc`, `typst`) exited non-zero.
    case processFailed(command: String, exitCode: Int32, stderr: String)

    /// A required binary could not be resolved (bundled, configured, or on PATH).
    case binaryUnavailable(name: String)

    /// The network is unreachable or the request timed out. Treated as a normal,
    /// non-alarming state per §5.5 — queue and retry, don't surface as an error dialog.
    case offline

    /// The stored GitHub credential was rejected. Distinct from `.offline` so the UI
    /// can prompt for re-authentication specifically rather than showing a generic
    /// connectivity failure (§12.2 item 4).
    case authenticationFailed

    /// A non-fast-forward push was rejected after a retry.
    case pushRejected

    /// Diverged history with the same paragraph edited on both sides (§5.7).
    case mergeConflict(paths: [String])

    /// A write target is not on local disk backed storage (§12.1) — Box, Dropbox,
    /// iCloud Drive, Google Drive, OneDrive.
    case locationInsideSyncedFolder(path: String)

    /// The working tree changed on disk out from under an open project (§12.2 item 1).
    case projectFolderMoved

    case filesystem(underlying: String)
}
