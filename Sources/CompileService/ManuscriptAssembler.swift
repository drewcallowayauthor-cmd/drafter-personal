import Foundation
import ProjectStore

/// Reads one scene file's raw contents. Injected so assembly can be unit tested against
/// in-memory fixtures rather than real files on disk.
public typealias SceneReader = @Sendable (URL) throws -> String

/// Walks a `BinderTree` into one assembled markdown stream (§9.1): strips YAML front
/// matter, skips scenes marked `compile: false`, emits a generated chapter heading per
/// `compile.chapterTitleFormat`, and joins scenes with `compile.sceneSeparator`.
public enum ManuscriptAssembler {
    /// Assembles `Manuscript/` into one stream. A chapter whose every scene is excluded
    /// (`compile: false`) is dropped entirely rather than emitting an empty heading, and
    /// chapter numbering only advances for chapters that actually appear in the output.
    public static func assembleManuscript(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> String {
        var emittedIndex = 0
        var chapters: [String] = []

        for chapter in binderTree.manuscript {
            let sceneBodies: [String]
            if chapter.isLooseFile {
                sceneBodies = try compiledBody(of: chapter.url, read: read).map { [$0] } ?? []
            } else {
                sceneBodies = try chapter.scenes.compactMap { try compiledBody(of: $0.url, read: read) }
            }

            guard !sceneBodies.isEmpty else { continue }

            emittedIndex += 1
            var chapterText = ""
            if let heading = ChapterHeadingFormatter.heading(
                format: compile.chapterTitleFormat,
                index: emittedIndex,
                title: chapter.displayName
            ) {
                chapterText += heading + "\n\n"
            }
            chapterText += sceneBodies.joined(separator: "\n\n\(compile.sceneSeparator)\n\n")
            chapters.append(chapterText)
        }

        return chapters.joined(separator: "\n\n")
    }

    /// Assembles a flat section (`FrontMatter/`, `BackMatter/`) with no generated
    /// headings — those files carry their own `#` headers (§9.1 point 5).
    public static func assembleMatter(_ scenes: [SceneNode], read: SceneReader) throws -> String {
        try scenes
            .map { SceneFrontMatter.parse(try read($0.url)).body }
            .joined(separator: "\n\n")
    }

    private static func compiledBody(of url: URL, read: SceneReader) throws -> String? {
        let (frontMatter, body) = SceneFrontMatter.parse(try read(url))
        return frontMatter.compile ? body : nil
    }

    /// The full assembly every export target needs: front matter (if enabled) +
    /// manuscript + back matter (if enabled), joined the same way regardless of which
    /// target (EPUB, print, DOCX) consumes the result. Shared so the three export
    /// coordinators don't each reimplement this toggle-checking.
    public static func assembleFull(binderTree: BinderTree, compile: ProjectMetadata.Compile, read: SceneReader) throws -> String {
        var parts: [String] = []
        if compile.includeFrontMatter, !binderTree.frontMatter.isEmpty {
            parts.append(try assembleMatter(binderTree.frontMatter, read: read))
        }
        parts.append(try assembleManuscript(binderTree: binderTree, compile: compile, read: read))
        if compile.includeBackMatter, !binderTree.backMatter.isEmpty {
            parts.append(try assembleMatter(binderTree.backMatter, read: read))
        }
        return parts.joined(separator: "\n\n")
    }
}
