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

        let assembled = try assembleWithContentsPage(binderTree: binderTree, compile: metadata.compile, read: read)

        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let metaURL = buildDirectory.appendingPathComponent("meta.yaml")
        try fileWriter.write(Data(EPUBMetadataGenerator.metaYAML(for: metadata).utf8), to: metaURL)

        let coverURL = workingTree.appendingPathComponent(metadata.compile.coverImage)
        let coverExists = FileManager.default.fileExists(atPath: coverURL.path)

        let sanitizedTitle = FilenamePrefix.sanitize(metadata.title)
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

    /// §11.1's assembly, plus a Contents page — unlike `FrontBackMatterTemplate`'s
    /// other five files, Contents isn't a static file at all, since its content (the
    /// real chapter list) isn't known until compile time. Matched against a finished
    /// Scrivener EPUB export: Contents sits right after Copyright, before Dedication —
    /// found by filename rather than by position, so a project that's renamed or
    /// deleted its Copyright file still gets *a* reasonable placement (the very start
    /// of Front Matter) instead of a thrown error.
    private func assembleWithContentsPage(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> String {
        var parts: [String] = []

        if compile.includeFrontMatter, !binderTree.frontMatter.isEmpty {
            let copyrightIndex = binderTree.frontMatter.firstIndex {
                FrontBackMatterTemplate.matching(filename: $0.url.lastPathComponent) == .copyright
            }
            let splitIndex = copyrightIndex.map { binderTree.frontMatter.index(after: $0) } ?? binderTree.frontMatter.startIndex

            let beforeContents = Array(binderTree.frontMatter[..<splitIndex])
            let afterContents = Array(binderTree.frontMatter[splitIndex...])

            if !beforeContents.isEmpty {
                parts.append(try ManuscriptAssembler.assembleMatter(beforeContents, read: read))
            }
            let contentsMarkdown = EPUBTableOfContentsGenerator.markdown(
                entries: try tableOfContentsEntries(binderTree: binderTree, compile: compile, read: read)
            )
            if !contentsMarkdown.isEmpty {
                parts.append(contentsMarkdown)
            }
            if !afterContents.isEmpty {
                parts.append(try ManuscriptAssembler.assembleMatter(afterContents, read: read))
            }
        }

        parts.append(try ManuscriptAssembler.assembleManuscript(binderTree: binderTree, compile: compile, read: read))

        if compile.includeBackMatter, !binderTree.backMatter.isEmpty {
            parts.append(try ManuscriptAssembler.assembleMatter(binderTree.backMatter, read: read))
        }

        return parts.joined(separator: "\n\n")
    }

    /// Every section that actually appears in the compiled output, in reading order —
    /// front matter template files (§ FrontBackMatterTemplate.contentsLabel), then
    /// chapters (§ ManuscriptAssembler.chapterEntries), then back matter template
    /// files. A front/back matter file that isn't one of the six standard templates
    /// (a custom addition) has no fixed anchor to link to, so it's left out rather
    /// than guessed at.
    private func tableOfContentsEntries(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> [EPUBTableOfContentsGenerator.Entry] {
        var entries: [EPUBTableOfContentsGenerator.Entry] = []

        if compile.includeFrontMatter {
            for scene in binderTree.frontMatter {
                if let template = FrontBackMatterTemplate.matching(filename: scene.url.lastPathComponent) {
                    entries.append(.init(title: template.contentsLabel, anchorID: template.anchorID))
                }
            }
        }

        entries += try ManuscriptAssembler.chapterEntries(binderTree: binderTree, compile: compile, read: read)
            .map { .init(title: $0.title, anchorID: $0.anchorID) }

        if compile.includeBackMatter {
            for scene in binderTree.backMatter {
                if let template = FrontBackMatterTemplate.matching(filename: scene.url.lastPathComponent) {
                    entries.append(.init(title: template.contentsLabel, anchorID: template.anchorID))
                }
            }
        }

        return entries
    }
}
