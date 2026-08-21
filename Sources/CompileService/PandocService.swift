import DrafterCore
import Foundation

/// Subprocess wrapper around `pandoc` (§2, §9.3). Unlike `GitService`, this never
/// throws on a non-zero exit — §9.6 requires showing pandoc's stderr verbatim on
/// export failure, never swallowed behind a generic message, so the caller needs the
/// raw result to decide how to present it rather than losing it to a thrown error.
public actor PandocService {
    private let processRunner: ProcessRunning
    private let pandocExecutableURL: URL

    public init(processRunner: ProcessRunning, pandocExecutableURL: URL) {
        self.processRunner = processRunner
        self.pandocExecutableURL = pandocExecutableURL
    }

    public func run(arguments: [String], in workingDirectory: URL) async throws -> ProcessResult {
        try await processRunner.run(
            executableURL: pandocExecutableURL,
            arguments: arguments,
            currentDirectoryURL: workingDirectory,
            environment: nil
        )
    }

    /// §9.3's EPUB export command. Cover image and stylesheet are optional since a
    /// project may not have a cover yet or may be using pandoc's epub3 defaults.
    public func exportEPUB(
        assembledMarkdownPath: String,
        metadataYAMLPath: String,
        cssPath: String?,
        coverImagePath: String?,
        outputPath: String,
        in workingDirectory: URL
    ) async throws -> ProcessResult {
        var arguments = [
            assembledMarkdownPath,
            "--from=markdown+smart",
            "--to=epub3",
            "--metadata-file=\(metadataYAMLPath)",
            // A CLI flag, not a metadata variable (verified against a real pandoc
            // build — `titlepage: false` in the metadata file is silently ignored;
            // this is the only thing that actually suppresses pandoc's own
            // auto-generated title page, which would otherwise sit right alongside
            // our own hand-authored, user-editable Title Page front-matter file).
            "--epub-title-page=false"
        ]
        if let coverImagePath {
            arguments.append("--epub-cover-image=\(coverImagePath)")
        }
        if let cssPath {
            arguments.append("--css=\(cssPath)")
        }
        // No `--toc`: that flag doesn't just build the EPUB3 nav document (pandoc
        // writes that unconditionally, spec-required) — it also inserts it as a
        // *linear* page early in the reading order, which duplicated our own
        // hand-authored Contents page (§ EPUBTableOfContentsGenerator). Verified
        // against a real pandoc build: without `--toc`, `nav.xhtml` is still written
        // and still usable by a reading app's own built-in TOC button, just not
        // forced into the flip-through page order. `--split-level=1` doesn't depend
        // on `--toc` — verified that too.
        arguments += ["--split-level=1", "-o", outputPath]

        return try await run(arguments: arguments, in: workingDirectory)
    }
}
