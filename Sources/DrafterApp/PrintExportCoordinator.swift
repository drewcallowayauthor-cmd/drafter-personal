import CompileService
import DrafterCore
import Foundation
import PDFKit
import ProjectStore

/// Orchestrates §9.4's print PDF export: pandoc converts assembled markdown straight to
/// a full Typst document (via `TypstDocumentGenerator`'s custom template), then typst
/// compiles it to PDF. Gutter depends on final page count, which depends on layout, so
/// this compiles once, reads the real page count back via PDFKit, and recompiles with
/// the correct gutter if it crosses a threshold (§9.4) — capped at two passes, since a
/// gutter change is small enough relative to page count that a second threshold
/// crossing from the recompile itself isn't a realistic case.
@MainActor
final class PrintExportCoordinator {
    struct ExportResult: Equatable {
        let outputURL: URL
        let pageCount: Int
    }

    private let processRunner: ProcessRunning
    private let fileWriter: AtomicFileWriting

    init(processRunner: ProcessRunning, fileWriter: AtomicFileWriting) {
        self.processRunner = processRunner
        self.fileWriter = fileWriter
    }

    func export(
        metadata: ProjectMetadata,
        binderTree: BinderTree,
        workingTree: URL,
        outputDirectory: URL,
        pandocExecutableURL: URL,
        typstExecutableURL: URL,
        trimSize: TrimSize,
        /// Extra directories typst should search for fonts — how a bundled font
        /// (§ `BundledFonts`) is found without being installed on the Mac.
        fontDirectoryURLs: [URL] = [],
        read: @escaping SceneReader = { try String(contentsOf: $0, encoding: .utf8) },
        // Both injectable so orchestration is testable without pandoc/typst actually
        // touching disk: readGeneratedTypst reads pandoc's own output file (not
        // something written through fileWriter, since pandoc writes it directly) back
        // in to patch the scene-break ornament; pageCounter defaults to actually
        // reading the compiled PDF back via PDFKit.
        readGeneratedTypst: @escaping (URL) throws -> String = { try String(contentsOf: $0, encoding: .utf8) },
        pageCounter: @escaping (URL) -> Int? = { PDFDocument(url: $0)?.pageCount }
    ) async throws -> ExportResult {
        let buildDirectory = workingTree.appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let assembled = try ManuscriptAssembler.assembleFull(
            binderTree: binderTree, compile: metadata.compile, read: read
        )
        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let metadataURL = buildDirectory.appendingPathComponent("print-meta.yaml")
        try fileWriter.write(Data(printMetadataYAML(for: metadata).utf8), to: metadataURL)

        let pandocService = PandocService(processRunner: processRunner, pandocExecutableURL: pandocExecutableURL)
        let typstService = TypstService(processRunner: processRunner, typstExecutableURL: typstExecutableURL)

        let templateResult = try await pandocService.run(
            arguments: ["--print-default-template=typst"], in: buildDirectory
        )
        guard templateResult.succeeded else {
            throw DrafterError.processFailed(
                command: "pandoc --print-default-template=typst",
                exitCode: templateResult.exitCode,
                stderr: templateResult.standardError
            )
        }
        let pandocDefaultTemplate = templateResult.standardOutput

        let sanitizedTitle = FilenamePrefix.sanitize(metadata.title)
        let outputURL = outputDirectory.appendingPathComponent("\(sanitizedTitle) - interior.pdf")
        let templateURL = buildDirectory.appendingPathComponent("template.typ")
        let mainTypstURL = buildDirectory.appendingPathComponent("main.typ")

        var gutter = GutterCalculator.gutterInches(forPageCount: 1)
        var pageCount = 0

        for pass in 1...2 {
            let templateContent = TypstDocumentGenerator.fullTemplate(
                pandocDefaultTemplate: pandocDefaultTemplate,
                trimSize: trimSize,
                gutterInches: gutter,
                print: metadata.print
            )
            try fileWriter.write(Data(templateContent.utf8), to: templateURL)

            let pandocResult = try await pandocService.run(
                arguments: [
                    assembledURL.path,
                    "--from=markdown+smart",
                    "--to=typst",
                    "--standalone",
                    "--template=\(templateURL.path)",
                    "--metadata-file=\(metadataURL.path)",
                    "-o", mainTypstURL.path
                ],
                in: buildDirectory
            )
            guard pandocResult.succeeded else {
                throw DrafterError.processFailed(
                    command: "pandoc", exitCode: pandocResult.exitCode, stderr: pandocResult.standardError
                )
            }

            let rawTypst = try readGeneratedTypst(mainTypstURL)
            let patchedTypst = TypstDocumentGenerator.applyFlushFirstParagraphAfterChapterHeadings(
                to: TypstDocumentGenerator.applyCenteredMatterStyling(
                    to: TypstDocumentGenerator.applySceneBreakOrnament(to: rawTypst),
                    bodyPointSize: metadata.print.bodyPointSize
                ),
                firstLineIndentEm: metadata.print.firstLineIndentEm
            )
            try fileWriter.write(Data(patchedTypst.utf8), to: mainTypstURL)

            let typstResult = try await typstService.compile(
                inputPath: mainTypstURL.path,
                outputPath: outputURL.path,
                fontPaths: fontDirectoryURLs.map(\.path),
                in: buildDirectory
            )
            guard typstResult.succeeded else {
                throw DrafterError.processFailed(
                    command: "typst compile", exitCode: typstResult.exitCode, stderr: typstResult.standardError
                )
            }

            guard let count = pageCounter(outputURL) else {
                throw DrafterError.processFailed(
                    command: "typst compile",
                    exitCode: 0,
                    stderr: "Compiled PDF at \(outputURL.path) could not be read back to check its page count."
                )
            }
            pageCount = count

            let neededGutter = GutterCalculator.gutterInches(forPageCount: pageCount)
            if neededGutter == gutter || pass == 2 {
                break
            }
            gutter = neededGutter
        }

        return ExportResult(outputURL: outputURL, pageCount: pageCount)
    }

    private func printMetadataYAML(for metadata: ProjectMetadata) -> String {
        "title: \(yamlString(metadata.title))\nauthor: \(yamlString(metadata.author))\n"
    }

    private func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
