import Foundation
import ProjectStore

/// Reads one scene file's raw contents. Injected so assembly can be unit tested against
/// in-memory fixtures rather than real files on disk.
public typealias SceneReader = @Sendable (URL) throws -> String

/// Walks a `BinderTree` into one assembled markdown stream (§9.1): strips YAML front
/// matter, skips scenes marked `compile: false`, emits a generated chapter heading per
/// `compile.chapterTitleFormat`, and joins scenes with `compile.sceneSeparator`.
public enum ManuscriptAssembler {
    /// A chapter that actually appears in the compiled output, alongside the heading
    /// text/anchor it was assembled with — `EPUBTableOfContentsGenerator` uses this
    /// (via `chapterEntries`) so the Contents page links line up exactly with what
    /// `assembleManuscript` emitted, without re-deriving the same numbering/skip
    /// rules a second time.
    public struct ChapterEntry: Equatable, Sendable {
        public let title: String
        public let anchorID: String
    }

    private struct AssembledChapter {
        let heading: String?
        let anchorID: String
        let body: String
    }

    /// Assembles `Manuscript/` into one stream. A chapter whose every scene is excluded
    /// (`compile: false`) is dropped entirely rather than emitting an empty heading, and
    /// chapter numbering only advances for chapters that actually appear in the output.
    public static func assembleManuscript(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> String {
        try assembleChapters(binderTree: binderTree, compile: compile, read: read)
            .map { chapter in
                var chapterText = ""
                if let heading = chapter.heading {
                    // A real level-1 Markdown heading, not a plain text line — §11.1's
                    // "front/back matter... carry their own `#` headers" only means
                    // the assembler generates this one instead of a scene author
                    // typing it; both consuming pipelines (the EPUB stylesheet's
                    // `.chapter-title` rule and the print template's
                    // `show heading.where(level: 1)`) need an actual heading here to
                    // apply their chapter-title styling and page breaks at all, and
                    // EPUB's `--split-level=1` needs one to split chapters into their
                    // own files. `.chapter-title` (vs. a bare, unclassed heading) is
                    // what gives chapters — and only chapters — the bold/underlined
                    // treatment; `{#anchor}` is what lets the Contents page link here
                    // precisely (§ ChapterEntry).
                    chapterText += "# " + heading + " {.chapter-title #\(chapter.anchorID)}\n\n"
                }
                chapterText += chapter.body
                return chapterText
            }
            .joined(separator: "\n\n")
    }

    /// The heading/anchor half of what `assembleManuscript` just built, for
    /// `EPUBTableOfContentsGenerator` — every chapter that got a heading in the
    /// compiled output (none did if `chapterTitleFormat` is `"none"`), in order.
    public static func chapterEntries(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> [ChapterEntry] {
        try assembleChapters(binderTree: binderTree, compile: compile, read: read)
            .compactMap { chapter in
                chapter.heading.map { ChapterEntry(title: $0, anchorID: chapter.anchorID) }
            }
    }

    /// The Short Story EPUB template's counterpart to `assembleManuscript` — a real
    /// finished short story's own compiled EPUB (Sunrise At Sundown, the reference
    /// used to build `EPUBStylesheetManager.shortStoryCSS`) has no "Chapter 1"/"Chapter
    /// 2" pagination at all: the whole story is *one* spine file, and what
    /// `chapterTitleFormat` numbers are bare in-line scene breaks, not separately
    /// paginated sections. `assembleManuscript`'s per-chapter `h1` defeats that —
    /// pandoc's `--split-level=1` (§ PandocService) fragments a new spine file *and* a
    /// new reader-nav entry at every `h1` it finds. So this wraps the whole manuscript
    /// in one invisible `h1.hidden-heading` (a single split/nav boundary, titled with
    /// the story's own title so `EPUBTableOfContentsGenerator`'s Contents page can link
    /// to it — same trick `FrontBackMatterTemplate.copyright` uses to be linkable
    /// without being visible) and demotes every chapter heading to `h2`, which
    /// `--split-level=1` leaves alone entirely — confirmed against a real pandoc build:
    /// mixed `h1`/`h2` markdown produces one spine file per `h1`, with `h2`s nested
    /// inside it, in both the spine and nav.xhtml.
    public static func assembleShortStoryManuscript(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        title: String,
        read: SceneReader
    ) throws -> String {
        let chapters = try assembleChapters(binderTree: binderTree, compile: compile, read: read)
        guard !chapters.isEmpty else { return "" }

        var text = "# " + title + " {.hidden-heading #\(manuscriptAnchorID)}\n\n"
        text += chapters
            .map { chapter in
                var chapterText = ""
                if let heading = chapter.heading {
                    chapterText += "## " + heading + " {#\(chapter.anchorID)}\n\n"
                }
                chapterText += chapter.body
                return chapterText
            }
            .joined(separator: "\n\n")
        return text
    }

    /// The one Contents-page entry `assembleShortStoryManuscript`'s wrapping heading
    /// needs — a Short Story export gets a single "the story's title" link instead of
    /// `chapterEntries`' one-per-chapter list, matching the single spine file it
    /// actually produced. `nil` when there's nothing to link to (an empty manuscript),
    /// mirroring `chapterEntries` returning `[]` in that case.
    public static func shortStoryContentsEntry(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        title: String,
        read: SceneReader
    ) throws -> ChapterEntry? {
        let chapters = try assembleChapters(binderTree: binderTree, compile: compile, read: read)
        guard !chapters.isEmpty else { return nil }
        return ChapterEntry(title: title, anchorID: manuscriptAnchorID)
    }

    private static let manuscriptAnchorID = "manuscript"

    private static func assembleChapters(
        binderTree: BinderTree,
        compile: ProjectMetadata.Compile,
        read: SceneReader
    ) throws -> [AssembledChapter] {
        var emittedIndex = 0
        var chapters: [AssembledChapter] = []

        for chapter in binderTree.manuscript {
            let sceneBodies: [String]
            if chapter.isLooseFile {
                sceneBodies = try compiledBody(of: chapter.url, read: read).map { [$0] } ?? []
            } else {
                sceneBodies = try chapter.scenes.compactMap { try compiledBody(of: $0.url, read: read) }
            }

            guard !sceneBodies.isEmpty else { continue }

            // A Prologue/Epilogue (§ ChapterHeadingFormatter.unnumberedTitles) doesn't
            // consume a chapter number — Chapter 1 stays Chapter 1 whether or not a
            // Prologue precedes it.
            if !ChapterHeadingFormatter.isUnnumbered(title: chapter.displayName) {
                emittedIndex += 1
            }
            let heading = ChapterHeadingFormatter.heading(
                format: compile.chapterTitleFormat,
                index: emittedIndex,
                title: chapter.displayName
            )
            let anchorID = ChapterHeadingFormatter.anchorID(index: emittedIndex, title: chapter.displayName)
            let body = sceneBodies.joined(separator: "\n\n\(compile.sceneSeparator)\n\n")
            chapters.append(AssembledChapter(heading: heading, anchorID: anchorID, body: body))
        }

        return chapters
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
    public static func assembleFull(
        binderTree: BinderTree, compile: ProjectMetadata.Compile, read: SceneReader
    ) throws -> String {
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
