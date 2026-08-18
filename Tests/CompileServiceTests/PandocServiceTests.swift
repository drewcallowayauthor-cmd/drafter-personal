import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import CompileService

@Suite("PandocService")
struct PandocServiceTests {
    private let workingDirectory = URL(fileURLWithPath: "/tmp/project/Build")
    private let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")

    @Test("exportEPUB builds the §9.3 command with cover and css included")
    func exportEPUBBuildsFullCommand() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let service = PandocService(processRunner: runner, pandocExecutableURL: pandocURL)

        _ = try await service.exportEPUB(
            assembledMarkdownPath: "assembled.md",
            metadataYAMLPath: "meta.yaml",
            cssPath: "epub.css",
            coverImagePath: "Resources/cover.jpg",
            outputPath: "../The Last Shift.epub",
            in: workingDirectory
        )

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == [
            "assembled.md",
            "--from=markdown+smart",
            "--to=epub3",
            "--metadata-file=meta.yaml",
            "--epub-cover-image=Resources/cover.jpg",
            "--css=epub.css",
            "--toc", "--toc-depth=1", "--split-level=1",
            "-o", "../The Last Shift.epub"
        ])
        #expect(invocations.first?.currentDirectoryURL == workingDirectory)
    }

    @Test("exportEPUB omits cover and css flags when neither is available")
    func exportEPUBOmitsMissingCoverAndCSS() async throws {
        let runner = MockProcessRunner()
        await runner.script(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "pandoc")
        let service = PandocService(processRunner: runner, pandocExecutableURL: pandocURL)

        _ = try await service.exportEPUB(
            assembledMarkdownPath: "assembled.md",
            metadataYAMLPath: "meta.yaml",
            cssPath: nil,
            coverImagePath: nil,
            outputPath: "out.epub",
            in: workingDirectory
        )

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments.contains { $0.hasPrefix("--epub-cover-image") } == false)
        #expect(invocations.first?.arguments.contains { $0.hasPrefix("--css") } == false)
    }

    @Test("a non-zero exit returns the result with stderr intact rather than throwing")
    func nonZeroExitReturnsResultNotThrow() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "pandoc: could not find style file epub.css"),
            forExecutableNamed: "pandoc"
        )
        let service = PandocService(processRunner: runner, pandocExecutableURL: pandocURL)

        let result = try await service.exportEPUB(
            assembledMarkdownPath: "assembled.md",
            metadataYAMLPath: "meta.yaml",
            cssPath: "missing.css",
            coverImagePath: nil,
            outputPath: "out.epub",
            in: workingDirectory
        )

        #expect(result.succeeded == false)
        #expect(result.standardError == "pandoc: could not find style file epub.css")
    }
}
