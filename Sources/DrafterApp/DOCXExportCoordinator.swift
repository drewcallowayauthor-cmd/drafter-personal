import CompileService
import DrafterCore
import Foundation
import ProjectStore

/// §9.5's DOCX fallback: assembles the manuscript and runs pandoc straight to `.docx`,
/// styled via a bundled `reference.docx` (`BundledDOCXTemplate`) for standard
/// submission-manuscript format — 12pt Times New Roman, double-spaced, no extra space
/// between paragraphs, 0.5in first-line indents, left-aligned, centered chapter
/// headings after a page break. That's the format agents/publishers expect from a
/// submitted manuscript, distinct from the finished-book look of the print PDF.
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
        referenceDocURL: URL? = BundledDOCXTemplate.referenceDocxURL,
        read: @escaping SceneReader = { try String(contentsOf: $0, encoding: .utf8) }
    ) async throws -> ExportResult {
        let buildDirectory = workingTree.appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let assembled = try ManuscriptAssembler.assembleFull(binderTree: binderTree, compile: metadata.compile, read: read)
        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let sanitizedTitle = FilenamePrefix.sanitize(metadata.title)
        let outputURL = outputDirectory.appendingPathComponent("\(sanitizedTitle).docx")

        var arguments = [assembledURL.path, "--from=markdown+smart", "--to=docx", "-o", outputURL.path]
        if let referenceDocURL {
            arguments.append("--reference-doc=\(referenceDocURL.path)")
        }

        let pandocService = PandocService(processRunner: processRunner, pandocExecutableURL: pandocExecutableURL)
        let result = try await pandocService.run(arguments: arguments, in: buildDirectory)
        guard result.succeeded else {
            throw DrafterError.processFailed(command: "pandoc", exitCode: result.exitCode, stderr: result.standardError)
        }

        return ExportResult(outputURL: outputURL)
    }
}
