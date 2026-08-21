import Foundation
import Testing
@testable import DrafterCore

@Suite("SyncedFolderGuard")
struct SyncedFolderGuardTests {
    private let home = URL(fileURLWithPath: "/Users/writer")

    @Test("a project inside iCloud Drive's CloudStorage folder is blocked")
    func blocksCloudStorage() {
        let url = home.appendingPathComponent("Library/CloudStorage/iCloud Drive/My Book")
        let error = SyncedFolderGuard.check(url, homeDirectory: home)
        #expect(error == .locationInsideSyncedFolder(path: url.path))
    }

    @Test("a project inside Dropbox is blocked")
    func blocksDropbox() {
        let url = home.appendingPathComponent("Dropbox/My Book")
        let error = SyncedFolderGuard.check(url, homeDirectory: home)
        #expect(error != nil)
    }

    @Test("a project under Documents/Drafter is allowed")
    func allowsDefaultLocation() {
        let url = home.appendingPathComponent("Documents/Drafter/Projects/My Book")
        let error = SyncedFolderGuard.check(url, homeDirectory: home)
        #expect(error == nil)
    }

    @Test("a folder that merely starts with the same prefix as a blocked name is not blocked")
    func doesNotFalsePositiveOnPrefixCollision() {
        let url = home.appendingPathComponent("Dropbox Backups/My Book")
        let error = SyncedFolderGuard.check(url, homeDirectory: home)
        #expect(error == nil)
    }
}
