import CompileService
import DrafterCore
import DrafterTestSupport
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

@MainActor
@Suite("DOCXExportCoordinator")
struct DOCXExportCoordinatorTests {
    private let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")

    @Test("assembles the manuscript and invokes pandoc --to=docx")
    func assemblesAndInvokesPandoc() async throws {
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
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let writer = MockAtomicFileWriter()
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: writer)

        let result = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            read: { _ in "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong." }
        )

        #expect(result.outputURL == root.appendingPathComponent("The Last Shift.docx"))
        let invocations = await runner.invocations
        let pandocArgs = invocations.first?.arguments ?? []
        #expect(pandocArgs.contains("--to=docx"))
        #expect(pandocArgs.contains(where: { $0.hasSuffix("The Last Shift.docx") }))

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("The board was wrong.") == true)
    }

    @Test("spells out the chapter number even when compile.chapterTitleFormat uses a bare numeral")
    func spellsOutChapterNumber() async throws {
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
        var metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        metadata.compile.chapterTitleFormat = "Chapter {n}"

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let writer = MockAtomicFileWriter()
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            read: { _ in "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong." }
        )

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("Chapter One") == true)
        #expect(assembledContent?.contains("Chapter 1") == false)
    }

    @Test("title page word count excludes the chapter-opener spacer's raw openxml markup")
    func wordCountExcludesSpacerMarkup() async throws {
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
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let writer = MockAtomicFileWriter()
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            read: { _ in "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong." }
        )

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        // "The board was wrong." is 4 words, rounding to 0; the spacer's raw openxml
        // (many attribute-shaped tokens like `w:val="ChapterSpacer"`) would inflate
        // this well past 0 if it leaked into the count.
        #expect(assembledContent?.contains("0 words.") == true)
    }

    @Test("ends the assembled manuscript with a centered * * * marker")
    func endsWithManuscriptMarker() async throws {
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
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let writer = MockAtomicFileWriter()
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            read: { _ in "---\nstatus: draft\ncompile: true\n---\n\nThe board was wrong." }
        )

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("<w:pStyle w:val=\"SMFEndMark\" />") == true)
        #expect(assembledContent?.contains("<w:t>* * *</w:t>") == true)
        #expect(assembledContent?.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("```") == true)
    }

    @Test("omits the * * * marker for an empty manuscript")
    func omitsMarkerForEmptyManuscript() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let writer = MockAtomicFileWriter()
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: writer)

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            read: { _ in "" }
        )

        let assembledContent = writer.writes.first { $0.url.lastPathComponent == "assembled.md" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        #expect(assembledContent?.contains("<w:t>* * *</w:t>") == false)
    }

    @Test("passes the bundled reference.docx to pandoc for submission-manuscript styling")
    func passesReferenceDocByDefault() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            referenceDocURL: URL(fileURLWithPath: "/some/reference.docx"),
            read: { _ in "" }
        )

        let invocations = await runner.invocations
        let pandocArgs = invocations.first?.arguments ?? []
        #expect(pandocArgs.contains("--reference-doc=/some/reference.docx"))
    }

    @Test("omits --reference-doc when no reference document is available")
    func omitsReferenceDocWhenNil() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        _ = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            referenceDocURL: nil,
            read: { _ in "" }
        )

        let invocations = await runner.invocations
        let pandocArgs = invocations.first?.arguments ?? []
        #expect(pandocArgs.contains(where: { $0.hasPrefix("--reference-doc=") }) == false)
    }

    @Test("a pandoc failure throws with stderr intact")
    func pandocFailureThrows() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "pandoc: unknown writer"),
            forExecutableNamed: "pandoc"
        )
        let coordinator = DOCXExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        await #expect(throws: DrafterError.self) {
            try await coordinator.export(
                metadata: metadata,
                binderTree: tree,
                workingTree: root,
                outputDirectory: root,
                pandocExecutableURL: pandocURL,
                read: { _ in "" }
            )
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
