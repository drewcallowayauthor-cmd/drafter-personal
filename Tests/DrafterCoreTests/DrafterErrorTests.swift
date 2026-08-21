import Foundation
import Testing
@testable import DrafterCore

/// Every `DrafterError` case must resolve to a real, non-empty message — the UI's
/// `.alert`/`errorMessage`/toast infrastructure surfaces `errorDescription` directly,
/// so a case with no message would render as a blank or generic alert with no clue
/// what went wrong.
@Suite("DrafterError localized descriptions")
struct DrafterErrorTests {
    private static let allCases: [DrafterError] = [
        .processFailed(command: "git push", exitCode: 1, stderr: "fatal: could not read"),
        .processFailed(command: "git push", exitCode: 1, stderr: ""),
        .binaryUnavailable(name: "pandoc"),
        .offline,
        .authenticationFailed,
        .pushRejected,
        .mergeConflict(paths: ["Manuscript/01 Arrival/01 Triage.md"]),
        .mergeConflict(paths: ["a.md", "b.md"]),
        .locationInsideSyncedFolder(path: "/Users/tester/Dropbox/Book"),
        .githubAPIError(statusCode: 422, message: "name already exists on this account"),
        .keychainFailed(status: -25300),
        .projectFolderMoved,
        .projectAlreadyOpen(path: "/Users/tester/Documents/Drafter/Projects/book"),
        .filesystem(underlying: "no such file"),
        .processLaunchFailed(name: "git", underlying: "no such file")
    ]

    @Test("every case has a non-empty errorDescription", arguments: allCases)
    func hasNonEmptyDescription(_ error: DrafterError) {
        let description = error.errorDescription
        #expect(description != nil)
        #expect(description?.isEmpty == false)
    }

    @Test("localizedDescription resolves to errorDescription, not the default NSError fallback")
    func localizedDescriptionUsesErrorDescription() {
        let error = DrafterError.offline
        #expect((error as NSError).localizedDescription == error.errorDescription)
    }
}
