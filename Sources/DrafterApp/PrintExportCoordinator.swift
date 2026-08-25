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

    /// Everything `export(_:)` needs to run, bundled into one value so the entry
    /// point stays under SwiftLint's parameter-count limit.
    struct ExportRequest {
        let metadata: ProjectMetadata
        let binderTree: BinderTree
        let workingTree: URL
        let outputDirectory: URL
        let pandocExecutableURL: URL
        let typstExecutableURL: URL
        let trimSize: TrimSize
        /// Extra directories typst should search for fonts — how a bundled font
        /// (§ `BundledFonts`) is found without being installed on the Mac.
        var fontDirectoryURLs: [URL] = []
    }

    /// Fixed inputs to a single compile pass, gathered once per `export(_:)` call so
    /// `compilePass(_:gutter:)` itself only needs the one value that varies between passes.
    private struct PassContext {
        let pandocService: PandocService
        let typstService: TypstService
        let buildDirectory: URL
        let assembledURL: URL
        let metadataURL: URL
        let templateURL: URL
        let mainTypstURL: URL
        let outputURL: URL
        let pandocDefaultTemplate: String
        let trimSize: TrimSize
        let print: ProjectMetadata.Print
        let fontDirectoryURLs: [URL]
        let readGeneratedTypst: (URL) throws -> String
        let pageCounter: (URL) -> Int?
    }

    private let processRunner: ProcessRunning
    private let fileWriter: AtomicFileWriting

    init(processRunner: ProcessRunning, fileWriter: AtomicFileWriting) {
        self.processRunner = processRunner
        self.fileWriter = fileWriter
    }

    func export(
        _ request: ExportRequest,
        read: @escaping SceneReader = { try String(contentsOf: $0, encoding: .utf8) },
        // Both injectable so orchestration is testable without pandoc/typst actually
        // touching disk: readGeneratedTypst reads pandoc's own output file (not
        // something written through fileWriter, since pandoc writes it directly) back
        // in to patch the scene-break ornament; pageCounter defaults to actually
        // reading the compiled PDF back via PDFKit.
        readGeneratedTypst: @escaping (URL) throws -> String = { try String(contentsOf: $0, encoding: .utf8) },
        pageCounter: @escaping (URL) -> Int? = { PDFDocument(url: $0)?.pageCount }
    ) async throws -> ExportResult {
        let buildDirectory = request.workingTree.appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let assembled = try ManuscriptAssembler.assembleFull(
            binderTree: request.binderTree, compile: request.metadata.compile, read: read
        )
        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let metadataURL = buildDirectory.appendingPathComponent("print-meta.yaml")
        try fileWriter.write(Data(printMetadataYAML(for: request.metadata).utf8), to: metadataURL)

        let pandocService = PandocService(
            processRunner: processRunner, pandocExecutableURL: request.pandocExecutableURL
        )
        let typstService = TypstService(
            processRunner: processRunner, typstExecutableURL: request.typstExecutableURL
        )
        let pandocDefaultTemplate = try await fetchPandocDefaultTemplate(
            pandocService: pandocService, buildDirectory: buildDirectory
        )

        let sanitizedTitle = FilenamePrefix.sanitize(request.metadata.title)
        let outputURL = request.outputDirectory.appendingPathComponent("\(sanitizedTitle) - interior.pdf")

        let context = PassContext(
            pandocService: pandocService,
            typstService: typstService,
            buildDirectory: buildDirectory,
            assembledURL: assembledURL,
            metadataURL: metadataURL,
            templateURL: buildDirectory.appendingPathComponent("template.typ"),
            mainTypstURL: buildDirectory.appendingPathComponent("main.typ"),
            outputURL: outputURL,
            pandocDefaultTemplate: pandocDefaultTemplate,
            trimSize: request.trimSize,
            print: request.metadata.print,
            fontDirectoryURLs: request.fontDirectoryURLs,
            readGeneratedTypst: readGeneratedTypst,
            pageCounter: pageCounter
        )

        var gutter = GutterCalculator.gutterInches(forPageCount: 1)
        var pageCount = 0

        for pass in 1...2 {
            pageCount = try await compilePass(context, gutter: gutter)
            let neededGutter = GutterCalculator.gutterInches(forPageCount: pageCount)
            if neededGutter == gutter || pass == 2 {
                break
            }
            gutter = neededGutter
        }

        return ExportResult(outputURL: outputURL, pageCount: pageCount)
    }

    private func fetchPandocDefaultTemplate(
        pandocService: PandocService, buildDirectory: URL
    ) async throws -> String {
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
        return templateResult.standardOutput
    }

    private func compilePass(_ context: PassContext, gutter: Double) async throws -> Int {
        let templateContent = TypstDocumentGenerator.fullTemplate(
            pandocDefaultTemplate: context.pandocDefaultTemplate,
            trimSize: context.trimSize,
            gutterInches: gutter,
            print: context.print
        )
        try fileWriter.write(Data(templateContent.utf8), to: context.templateURL)
        try await runPandocToTypst(context)
        return try await compileTypstToPDF(context)
    }

    private func runPandocToTypst(_ context: PassContext) async throws {
        let pandocResult = try await context.pandocService.run(
            arguments: [
                context.assembledURL.path,
                "--from=markdown+smart",
                "--to=typst",
                "--standalone",
                "--template=\(context.templateURL.path)",
                "--metadata-file=\(context.metadataURL.path)",
                "-o", context.mainTypstURL.path
            ],
            in: context.buildDirectory
        )
        guard pandocResult.succeeded else {
            throw DrafterError.processFailed(
                command: "pandoc", exitCode: pandocResult.exitCode, stderr: pandocResult.standardError
            )
        }

        let rawTypst = try context.readGeneratedTypst(context.mainTypstURL)
        let patchedTypst = TypstDocumentGenerator.applyFlushFirstParagraphAfterChapterHeadings(
            to: TypstDocumentGenerator.applyCenteredMatterStyling(
                to: TypstDocumentGenerator.applySceneBreakOrnament(to: rawTypst),
                bodyPointSize: context.print.bodyPointSize
            ),
            firstLineIndentEm: context.print.firstLineIndentEm
        )
        try fileWriter.write(Data(patchedTypst.utf8), to: context.mainTypstURL)
    }

    private func compileTypstToPDF(_ context: PassContext) async throws -> Int {
        let typstResult = try await context.typstService.compile(
            inputPath: context.mainTypstURL.path,
            outputPath: context.outputURL.path,
            fontPaths: context.fontDirectoryURLs.map(\.path),
            in: context.buildDirectory
        )
        guard typstResult.succeeded else {
            throw DrafterError.processFailed(
                command: "typst compile", exitCode: typstResult.exitCode, stderr: typstResult.standardError
            )
        }

        guard let count = context.pageCounter(context.outputURL) else {
            throw DrafterError.processFailed(
                command: "typst compile",
                exitCode: 0,
                stderr: "Compiled PDF at \(context.outputURL.path) could not be read back to check its page count."
            )
        }
        return count
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
