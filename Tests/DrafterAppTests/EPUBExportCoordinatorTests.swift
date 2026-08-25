import CompileService
import DrafterCore
import DrafterTestSupport
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

@MainActor
@Suite("EPUBExportCoordinator")
struct EPUBExportCoordinatorTests {
    private let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")

    @Test("writes assembled.md and meta.yaml, then invokes pandoc with their paths")
    func writesFilesAndInvokesPandoc() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sceneURL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let chapter = ChapterNode(
            url: root.appendingPathComponent("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(manuscript: [chapter], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc"
        )
        let writer = MockAtomicFileWriter()
        let coordinator = EPUBExportCoordinator(processRunner: runner, fileWriter: writer)

        let result = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            cssURL: nil,
            read: { _ in "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong." }
        )

        #expect(result.outputURL == root.appendingPathComponent("Last Call.epub"))
        #expect(result.wordCount > 0)

        let writtenPaths = writer.writes.map(\.url.lastPathComponent)
        #expect(writtenPaths.contains("assembled.md"))
        #expect(writtenPaths.contains("meta.yaml"))

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("The board was wrong.") == true)

        let invocations = await runner.invocations
        let pandocArgs = invocations.first?.arguments ?? []
        #expect(pandocArgs.contains("--to=epub3"))
        #expect(pandocArgs.contains(where: { $0.hasSuffix("assembled.md") }))
        #expect(pandocArgs.contains(where: { $0.hasSuffix("meta.yaml") }))
        #expect(pandocArgs.contains(where: { $0.hasSuffix("Last Call.epub") }))
    }

    @Test("a pandoc failure throws with stderr intact rather than silently succeeding")
    func pandocFailureThrows() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "pandoc: unknown option --bogus"),
            forExecutableNamed: "pandoc"
        )
        let coordinator = EPUBExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        await #expect(throws: DrafterError.self) {
            try await coordinator.export(
                metadata: metadata,
                binderTree: tree,
                workingTree: root,
                outputDirectory: root,
                pandocExecutableURL: pandocURL,
                cssURL: nil,
                read: { _ in "" }
            )
        }
    }

    @Test("includes front and back matter when the toggles are on")
    func includesFrontAndBackMatterWhenEnabled() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let frontURL = root.appendingPathComponent("FrontMatter/01 Title Page.md")
        let backURL = root.appendingPathComponent("BackMatter/01 About the Author.md")
        let tree = BinderTree(
            manuscript: [],
            frontMatter: [SceneNode(url: frontURL, displayName: "Title Page")],
            backMatter: [SceneNode(url: backURL, displayName: "About the Author")],
            notes: []
        )
        var metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)
        metadata.compile.includeFrontMatter = true
        metadata.compile.includeBackMatter = true

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc"
        )
        let writer = MockAtomicFileWriter()
        let coordinator = EPUBExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            cssURL: nil,
            read: { url in url == frontURL ? "# Title Page" : "# About the Author" }
        )

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("# Title Page") == true)
        #expect(assembledContent?.contains("# About the Author") == true)
    }

    @Test("splices a Contents page in right after Copyright, with links to every section")
    func splicesContentsPageAfterCopyright() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let titlePageURL = root.appendingPathComponent("FrontMatter/01 Title Page.md")
        let copyrightURL = root.appendingPathComponent("FrontMatter/02 Copyright.md")
        let dedicationURL = root.appendingPathComponent("FrontMatter/03 Dedication.md")
        let sceneURL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let chapter = ChapterNode(
            url: root.appendingPathComponent("Manuscript/01 Arrival"),
            displayName: "Arrival",
            scenes: [SceneNode(url: sceneURL, displayName: "Triage")],
            isLooseFile: false
        )
        let tree = BinderTree(
            manuscript: [chapter],
            frontMatter: [
                SceneNode(url: titlePageURL, displayName: "Title Page"),
                SceneNode(url: copyrightURL, displayName: "Copyright"),
                SceneNode(url: dedicationURL, displayName: "Dedication")
            ],
            backMatter: [],
            notes: []
        )
        let contents: [URL: String] = [
            titlePageURL: FrontBackMatterTemplate.titlePage.content(for: metadata),
            copyrightURL: FrontBackMatterTemplate.copyright.content(for: metadata),
            dedicationURL: FrontBackMatterTemplate.dedication.content(for: metadata),
            sceneURL: "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong."
        ]

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc"
        )
        let writer = MockAtomicFileWriter()
        let coordinator = EPUBExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            cssURL: nil,
            read: { contents[$0]! }
        )

        let assembled = try #require(
            writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
                .flatMap { String(data: $0.data, encoding: .utf8) }
        )

        #expect(assembled.contains("[Title Page](#title-page)"))
        #expect(assembled.contains("[Copyright](#copyright)"))
        #expect(assembled.contains("[Dedication](#dedication)"))
        #expect(assembled.contains("[Chapter 1](#chapter-1)"))

        // Contents itself sits after Copyright's body and before Dedication's.
        let copyrightBodyRange = try #require(assembled.range(of: "All rights reserved"))
        let contentsRange = try #require(assembled.range(of: "# Contents"))
        let dedicationRange = try #require(assembled.range(of: "# Dedication"))
        #expect(copyrightBodyRange.upperBound < contentsRange.lowerBound)
        #expect(contentsRange.upperBound < dedicationRange.lowerBound)
    }

    @Test("short story template assembles one hidden-heading manuscript with a single Contents entry")
    func shortStoryTemplateProducesOneContinuousSection() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = ProjectMetadata(title: "Rook Takes", author: "Drew Calloway", copyrightYear: 2026)

        let titlePageURL = root.appendingPathComponent("FrontMatter/01 Title Page.md")
        let copyrightURL = root.appendingPathComponent("FrontMatter/02 Copyright.md")
        let scene1URL = root.appendingPathComponent("Manuscript/01 Arrival/01 Triage.md")
        let scene2URL = root.appendingPathComponent("Manuscript/02 Departure/01 Goodbye.md")
        let chapters = [
            ChapterNode(
                url: root.appendingPathComponent("Manuscript/01 Arrival"),
                displayName: "Arrival",
                scenes: [SceneNode(url: scene1URL, displayName: "Triage")],
                isLooseFile: false
            ),
            ChapterNode(
                url: root.appendingPathComponent("Manuscript/02 Departure"),
                displayName: "Departure",
                scenes: [SceneNode(url: scene2URL, displayName: "Goodbye")],
                isLooseFile: false
            )
        ]
        let tree = BinderTree(
            manuscript: chapters,
            frontMatter: [
                SceneNode(url: titlePageURL, displayName: "Title Page"),
                SceneNode(url: copyrightURL, displayName: "Copyright")
            ],
            backMatter: [],
            notes: []
        )
        var exportMetadata = metadata
        exportMetadata.compile.includeFrontMatter = true
        exportMetadata.compile.chapterTitleFormat = "{n}"
        let contents: [URL: String] = [
            titlePageURL: FrontBackMatterTemplate.titlePage.content(for: metadata),
            copyrightURL: FrontBackMatterTemplate.copyright.content(for: metadata),
            scene1URL: "---\nstatus: draft\ncompile: true\n---\n\nFirst scene text.",
            scene2URL: "---\nstatus: draft\ncompile: true\n---\n\nSecond scene text."
        ]

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc"
        )
        let writer = MockAtomicFileWriter()
        let coordinator = EPUBExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: exportMetadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            cssURL: nil,
            epubTemplate: .shortStory,
            read: { contents[$0]! }
        )

        let assembled = try #require(
            writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
                .flatMap { String(data: $0.data, encoding: .utf8) }
        )

        // One Contents entry for the story title, not one per chapter.
        #expect(assembled.contains("[Rook Takes](#manuscript)"))
        #expect(assembled.contains("[1](#chapter-1)") == false)
        #expect(assembled.contains("[2](#chapter-2)") == false)

        // The manuscript itself is one hidden heading with bare numbered h2 scenes underneath.
        #expect(assembled.contains("# Rook Takes {.hidden-heading #manuscript}"))
        #expect(assembled.contains("## 1 {#chapter-1}"))
        #expect(assembled.contains("## 2 {#chapter-2}"))
        #expect(assembled.contains("# Chapter") == false)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
