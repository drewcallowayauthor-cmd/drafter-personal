import CompileService
import DrafterCore
import Foundation
import ProjectStore

/// Assembles the manuscript and runs pandoc straight to `.docx`, styled via a bundled
/// `reference.docx` (`BundledDOCXTemplate`) for real Standard Manuscript Format
/// (Shunn format): a generated title page (contact block, word count, centered
/// title/byline — see `SMFTitlePageBuilder`) instead of the app's book-style front
/// matter, a running `Lastname / TITLE / #` header on every page but the first, 12pt
/// Times New Roman or Courier New (`metadata.manuscript.bodyFont`), double-spaced,
/// 0.5in first-line indents, left-aligned, centered non-bold chapter headings after a
/// page break. Front/back matter is deliberately never included — not standard for a
/// submission manuscript. That's the format agents/publishers expect from a submitted
/// manuscript, distinct from the finished-book look of the print PDF/EPUB.
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

        let assembledChapters = try ManuscriptAssembler.assembleManuscript(
            binderTree: binderTree, compile: Self.spelledOutChapterCompile(metadata.compile), read: read
        )
        // Word count is taken before SMFChapterOpenerSpacer/SMFSceneSeparatorFormatter
        // splice their raw-OOXML paragraphs in — WordCounter only strips HTML
        // comments/markdown syntax, not raw `{=openxml}` blocks, so counting the
        // post-splice text would tally that XML's own attribute tokens as words.
        let wordCount = WordCounter.count(assembledChapters)
        let sceneSeparatorsFormatted = SMFSceneSeparatorFormatter.format(
            assembledChapters, separator: metadata.compile.sceneSeparator
        )
        var manuscriptBody = SMFChapterOpenerSpacer.insertSpacing(into: sceneSeparatorsFormatted)
        if !assembledChapters.isEmpty {
            manuscriptBody = SMFEndOfManuscriptMarker.append(to: manuscriptBody)
        }
        let titlePage = SMFTitlePageBuilder.build(metadata: metadata, wordCount: wordCount)
        let assembled = titlePage + "\n\n" + manuscriptBody
        let assembledURL = buildDirectory.appendingPathComponent("assembled.md")
        try fileWriter.write(Data(assembled.utf8), to: assembledURL)

        let sanitizedTitle = FilenamePrefix.sanitize(metadata.title)
        let outputURL = outputDirectory.appendingPathComponent("\(sanitizedTitle).docx")

        var arguments = [assembledURL.path, "--from=markdown+smart+raw_attribute", "--to=docx", "-o", outputURL.path]
        if let referenceDocURL {
            arguments.append("--reference-doc=\(referenceDocURL.path)")
        }

        let pandocService = PandocService(processRunner: processRunner, pandocExecutableURL: pandocExecutableURL)
        let result = try await pandocService.run(arguments: arguments, in: buildDirectory)
        guard result.succeeded else {
            throw DrafterError.processFailed(command: "pandoc", exitCode: result.exitCode, stderr: result.standardError)
        }

        // Headers/footers are copied verbatim from reference.docx by pandoc with no
        // per-project text substitution, and the body font is one fixed choice baked
        // into the reference doc's styles — both need a post-pass on the actual
        // generated file. Skipped when the file doesn't exist (e.g. a mocked test
        // process runner that never really invokes pandoc) rather than failing.
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try await patch(outputDocxAt: outputURL, metadata: metadata, buildDirectory: buildDirectory)
        }

        return ExportResult(outputURL: outputURL)
    }

    /// Standard Manuscript Format always spells chapter numbers out ("Chapter One"),
    /// regardless of whether the project's own `compile.chapterTitleFormat` — shared
    /// with the print/EPUB exports, which conventionally use bare numerals ("Chapter
    /// 1") — was set with numerals. Only swaps `{n}` for `{n_word}`; `"none"` and a
    /// format that already spells numbers out both pass through unchanged.
    private static func spelledOutChapterCompile(_ compile: ProjectMetadata.Compile) -> ProjectMetadata.Compile {
        var compile = compile
        if compile.chapterTitleFormat != "none", !compile.chapterTitleFormat.contains("{n_word}") {
            compile.chapterTitleFormat = compile.chapterTitleFormat.replacingOccurrences(of: "{n}", with: "{n_word}")
        }
        return compile
    }

    private func patch(outputDocxAt outputURL: URL, metadata: ProjectMetadata, buildDirectory: URL) async throws {
        let patchDirectory = buildDirectory.appendingPathComponent("docx-patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: patchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: patchDirectory) }

        _ = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-o", outputURL.path, "-d", patchDirectory.path],
            currentDirectoryURL: buildDirectory,
            environment: nil
        )

        let headerURL = patchDirectory.appendingPathComponent("word/header1.xml")
        if let headerXML = try? String(contentsOf: headerURL, encoding: .utf8) {
            let patched = DOCXHeaderPatcher.patchHeader(
                headerXML,
                authorLastName: SMFTitlePageBuilder.lastName(of: metadata.author),
                title: metadata.title.uppercased()
            )
            try patched.write(to: headerURL, atomically: true, encoding: .utf8)
        }

        let stylesURL = patchDirectory.appendingPathComponent("word/styles.xml")
        if let stylesXML = try? String(contentsOf: stylesURL, encoding: .utf8) {
            let patched = DOCXHeaderPatcher.applyBodyFont(metadata.manuscript.bodyFont, to: stylesXML)
            if patched != stylesXML {
                try patched.write(to: stylesURL, atomically: true, encoding: .utf8)
            }
        }

        try? FileManager.default.removeItem(at: outputURL)
        _ = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-r", "-X", outputURL.path, "."],
            currentDirectoryURL: patchDirectory,
            environment: nil
        )
    }
}
