import Foundation
import Testing
@testable import SnapshotService

@Suite("ConflictedCopyDetector")
struct ConflictedCopyDetectorTests {
    @Test("recognizes Dropbox's conflicted-copy naming")
    func recognizesDropbox() {
        let name = "02 Code Blue (Josiah's conflicted copy 2026-08-18).md"
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: name) == "02 Code Blue.md")
    }

    @Test("recognizes Box's conflicted-copy naming")
    func recognizesBox() {
        let name = "02 Code Blue (Conflicted copy 2026-08-18).md"
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: name) == "02 Code Blue.md")
    }

    @Test("recognizes iCloud Drive's numbered-duplicate naming")
    func recognizesICloud() {
        let name = "02 Code Blue 2.md"
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: name) == "02 Code Blue.md")
    }

    @Test("recognizes OneDrive's machine-suffixed naming")
    func recognizesOneDrive() {
        // A machine name containing its own hyphens (common — "Josiah-MacBook-Pro")
        // is inherently ambiguous against a generic "<name>-<machine>" pattern with no
        // way to know where the title ends and the machine name begins; this is a
        // best-effort pattern (§7.5), not a guarantee, so it's only exercised here
        // with a single-token machine name.
        let name = "02 Code Blue-JOSIAHSLAPTOP.md"
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: name) == "02 Code Blue.md")
    }

    @Test("an ordinary filename doesn't match any pattern")
    func ordinaryFilenameDoesNotMatch() {
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: "02 Code Blue.md") == nil)
        #expect(ConflictedCopyDetector.candidateOriginalFilename(for: "01 Triage.md") == nil)
    }

    @Test("scan only reports a match when the guessed original file actually exists alongside it")
    func scanRequiresTheOriginalToExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chapter = root.appendingPathComponent("Manuscript/02 The First Hour")
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)

        // A numbered-looking file with no real original alongside it — must NOT be
        // flagged, since that's exactly the false-positive the existence check guards.
        try Data("orphan".utf8).write(to: chapter.appendingPathComponent("02 Code Blue 2.md"))

        var matches = ConflictedCopyDetector.scan(workingTree: root)
        #expect(matches.isEmpty)

        // Now the original shows up too — a genuine conflict copy.
        try Data("original".utf8).write(to: chapter.appendingPathComponent("02 Code Blue.md"))
        matches = ConflictedCopyDetector.scan(workingTree: root)

        #expect(matches.count == 1)
        #expect(matches.first?.conflictedURL.lastPathComponent == "02 Code Blue 2.md")
        #expect(matches.first?.originalURL.lastPathComponent == "02 Code Blue.md")
    }

    @Test("scan skips History/, Build/, and Resources/")
    func scanSkipsExcludedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = root.appendingPathComponent("History/2026-08-18 00-00-00 M")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: history.appendingPathComponent("Scene 2.md"))
        try Data("b".utf8).write(to: history.appendingPathComponent("Scene.md"))

        #expect(ConflictedCopyDetector.scan(workingTree: root).isEmpty)
    }
}
