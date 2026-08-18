import CompileService
import DrafterCore
import Foundation
import ProjectStore

/// Orchestrates §9.1's assembly and §9.3's pandoc invocation into one EPUB export.
/// Binary resolution happens *before* this is called (`BinaryResolver`, a real
/// filesystem check) — this takes the resolved URL as a parameter so the orchestration
/// itself stays testable against mocks rather than the real pandoc binary.
@MainActor
final class EPUBExportCoordinator {
    struct ExportResult: Equatable {
        let outputURL: URL
        let wordCount: Int
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
        cssURL: URL?,
        read: @escaping SceneReader = { try String(contentsOf: $0, encoding: .utf8) }
    ) async throws -> ExportResult {
        let buildDirectory = workingTree.appendingPathComponent("Build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        var assembledParts: [String] = []
        if metadata.compile.includeFrontMatter, !binderTree.frontMatter.isEmpty {
            assembledParts.append(try ManuscriptAssembler.assembleMatter(binderTree.frontMatter, read: read))
        }
        let manuscript = try ManuscriptAssembler.assembleManuscript(binderTree: binderTree, compile: metadata.compile, read: read)
        assembledParts.append(manuscript)
        if metadata.compile.includeBackMatter, !binderTree.backMatter.isEmpty {
            assembledParts.append(try ManuscriptAssembler.assembleMatter(binderTree.backMatter, read: read))
        }
        let assembled = assembledParts.joined(separator: "\n\n")

        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let metaURL = buildDirectory.appendingPathComponent("meta.yaml")
        try fileWriter.write(Data(EPUBMetadataGenerator.metaYAML(for: metadata).utf8), to: metaURL)

        let coverURL = workingTree.appendingPathComponent(metadata.compile.coverImage)
        let coverExists = FileManager.default.fileExists(atPath: coverURL.path)

        let sanitizedTitle = metadata.title.isEmpty ? "Untitled" : metadata.title
        let outputURL = outputDirectory.appendingPathComponent("\(sanitizedTitle).epub")

        let pandocService = PandocService(processRunner: processRunner, pandocExecutableURL: pandocExecutableURL)
        let result = try await pandocService.exportEPUB(
            assembledMarkdownPath: assembledURL.path,
            metadataYAMLPath: metaURL.path,
            cssPath: cssURL?.path,
            coverImagePath: coverExists ? coverURL.path : nil,
            outputPath: outputURL.path,
            in: buildDirectory
        )

        guard result.succeeded else {
            throw DrafterError.processFailed(command: "pandoc", exitCode: result.exitCode, stderr: result.standardError)
        }

        return ExportResult(outputURL: outputURL, wordCount: WordCounter.count(assembled))
    }
}
