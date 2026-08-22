import CompileService
import DrafterCore
import DrafterTestSupport
import Foundation
import ProjectStore
import Testing
@testable import DrafterApp

@MainActor
@Suite("PrintExportCoordinator")
struct PrintExportCoordinatorTests {
    private let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")
    private let typstURL = URL(fileURLWithPath: "/usr/local/bin/typst")

    /// Enough of pandoc's real default typst template to exercise TypstDocumentGenerator's
    /// marker replacement, matching TypstDocumentGeneratorTests' fixture.
    private let fakeDefaultTemplate = """
        $if(template)$
        #import "$template$": conf
        $else$
        $template.typst()$
        $endif$
        $body$
        """

    @Test("compiles once when the page count doesn't cross a gutter threshold")
    func compilesOnceWhenGutterStaysTheSame() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: fakeDefaultTemplate, standardError: ""),
            forExecutableNamed: "pandoc"
        )
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "typst")
        let coordinator = PrintExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        let result = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            typstExecutableURL: typstURL,
            trimSize: .fiveByEight,
            read: { _ in "" },
            readGeneratedTypst: { _ in "" },
            pageCounter: { _ in 100 } // stays within the first gutter tier (<=150)
        )

        #expect(result.pageCount == 100)
        #expect(result.outputURL == root.appendingPathComponent("Last Call - interior.pdf"))

        let typstInvocations = await runner.invocations.filter { $0.executableURL == self.typstURL }
        #expect(typstInvocations.count == 1)
    }

    @Test("recompiles once with a larger gutter when the page count crosses a threshold")
    func recompilesWhenGutterThresholdCrossed() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: fakeDefaultTemplate, standardError: ""),
            forExecutableNamed: "pandoc"
        )
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "typst")
        let writer = MockAtomicFileWriter()
        let coordinator = PrintExportCoordinator(processRunner: runner, fileWriter: writer)

        // 400 pages needs the 301-500 tier (0.5in), not the <=150 tier (0.25in) the
        // first pass assumes — this should trigger exactly one recompile.
        let result = try await coordinator.export(
            metadata: metadata,
            binderTree: tree,
            workingTree: root,
            outputDirectory: root,
            pandocExecutableURL: pandocURL,
            typstExecutableURL: typstURL,
            trimSize: .fiveByEight,
            read: { _ in "" },
            readGeneratedTypst: { _ in "" },
            pageCounter: { _ in 400 }
        )

        #expect(result.pageCount == 400)
        let typstInvocations = await runner.invocations.filter { $0.executableURL == self.typstURL }
        #expect(typstInvocations.count == 2)

        let templateWrites = writer.writes.filter { $0.url.lastPathComponent == "template.typ" }
        #expect(templateWrites.count == 2)
        let firstGutter = String(data: templateWrites[0].data, encoding: .utf8)!
        let secondGutter = String(data: templateWrites[1].data, encoding: .utf8)!
        #expect(firstGutter.contains("inside: 0.75in"))
        #expect(secondGutter.contains("inside: 1.0in"))
    }

    @Test("a typst compile failure throws with stderr intact")
    func typstFailureThrows() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = BinderTree(manuscript: [], frontMatter: [], backMatter: [], notes: [])
        let metadata = ProjectMetadata(title: "Last Call", author: "Drew Calloway", copyrightYear: 2026)

        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: fakeDefaultTemplate, standardError: ""),
            forExecutableNamed: "pandoc"
        )
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "error: file not found"),
            forExecutableNamed: "typst"
        )
        let coordinator = PrintExportCoordinator(processRunner: runner, fileWriter: MockAtomicFileWriter())

        await #expect(throws: DrafterError.self) {
            try await coordinator.export(
                metadata: metadata,
                binderTree: tree,
                workingTree: root,
                outputDirectory: root,
                pandocExecutableURL: pandocURL,
                typstExecutableURL: typstURL,
                trimSize: .fiveByEight,
                read: { _ in "" },
                readGeneratedTypst: { _ in "" },
                pageCounter: { _ in 100 }
            )
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
