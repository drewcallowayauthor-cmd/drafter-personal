import CompileService
import DrafterCore
import Foundation
import ProjectStore

/// §9.5's DOCX fallback: assembles the manuscript and runs pandoc straight to `.docx`.
/// Scope note: §9.5 ships a custom `reference.docx` for sane Normal/Heading 1 styles;
/// v1 omits that and uses pandoc's own built-in defaults, which are fully functional —
/// flagged here rather than silently built in, the same way epub.css and the print
/// template's continuous (non-roman-front-matter) page numbering are flagged.
@MainActor
final class DOCXExportCoordinator {
    struct ExportResult: Equatable {
        let outputURL: URL
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
        read: @escaping SceneReader = { try String(contentsOf: $0, encoding: .utf8) }
    ) async throws -> ExportResult {
        let buildDirectory = workingTree.appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let assembled = try ManuscriptAssembler.assembleFull(binderTree: binderTree, compile: metadata.compile, read: read)
        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let sanitizedTitle = metadata.title.isEmpty ? "Untitled" : metadata.title
        let outputURL = outputDirectory.appendingPathComponent("\(sanitizedTitle).docx")

        let pandocService = PandocService(processRunner: processRunner, pandocExecutableURL: pandocExecutableURL)
        let result = try await pandocService.run(
            arguments: [assembledURL.path, "--from=markdown+smart", "--to=docx", "-o", outputURL.path],
            in: buildDirectory
        )
        guard result.succeeded else {
            throw DrafterError.processFailed(command: "pandoc", exitCode: result.exitCode, stderr: result.standardError)
        }

        return ExportResult(outputURL: outputURL)
    }
}
