import DrafterCore
import Foundation
import Testing
@testable import DrafterApp

@Suite("EPUBStylesheetManager")
struct EPUBStylesheetManagerTests {
    @Test("Novel writes epub.css; Short Story writes its own file, neither touching the other")
    func templatesWriteSeparateFiles() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let novelURL = try EPUBStylesheetManager.ensureStylesheetExists(
            template: .novel,
            fileWriter: LiveAtomicFileWriter(),
            directoryOverride: directory
        )
        let shortStoryURL = try EPUBStylesheetManager.ensureStylesheetExists(
            template: .shortStory,
            fileWriter: LiveAtomicFileWriter(),
            directoryOverride: directory
        )

        #expect(novelURL.lastPathComponent == "epub.css")
        #expect(shortStoryURL.lastPathComponent == "epub-short-story.css")
        #expect(try String(contentsOf: novelURL, encoding: .utf8) == EPUBStylesheetManager.defaultCSS)
        #expect(try String(contentsOf: shortStoryURL, encoding: .utf8) == EPUBStylesheetManager.shortStoryCSS)
    }

    @Test("an existing hand-edited stylesheet is left untouched")
    func existingStylesheetLeftUntouched() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let novelURL = directory.appendingPathComponent("epub.css")
        try Data("Hand-edited content.".utf8).write(to: novelURL)

        _ = try EPUBStylesheetManager.ensureStylesheetExists(
            template: .novel,
            fileWriter: LiveAtomicFileWriter(),
            directoryOverride: directory
        )

        #expect(try String(contentsOf: novelURL, encoding: .utf8) == "Hand-edited content.")
    }

    @Test("Short Story's chapter heading is plain, unlike Novel's bold boxed treatment")
    func shortStoryHeadingIsPlain() {
        #expect(EPUBStylesheetManager.defaultCSS.contains("font-weight: bold"))
        #expect(EPUBStylesheetManager.defaultCSS.contains("border-bottom: 2px solid currentColor"))
        #expect(EPUBStylesheetManager.shortStoryCSS.contains("font-weight: bold") == false)
        #expect(EPUBStylesheetManager.shortStoryCSS.contains("border-bottom: 2px solid currentColor") == false)
    }

    @Test("Short Story's numbered scene breaks (h2) don't force a page break, unlike its h1 chapter files")
    func shortStorySceneBreaksDontPageBreak() throws {
        #expect(EPUBStylesheetManager.shortStoryCSS.contains("h1 {\n  page-break-before: always;"))
        #expect(EPUBStylesheetManager.shortStoryCSS.contains("h2 {\n  margin:"))
        // The h2 rule block itself carries no page-break-before.
        let h2RuleRange = try #require(
            EPUBStylesheetManager.shortStoryCSS.range(of: "h2 \\{[^}]*\\}", options: .regularExpression)
        )
        #expect(EPUBStylesheetManager.shortStoryCSS[h2RuleRange].contains("page-break-before") == false)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
