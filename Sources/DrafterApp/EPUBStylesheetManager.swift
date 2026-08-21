import DrafterCore
import Foundation

/// §9.3's `epub.css`: shipped as an editable file in Application Support, not
/// regenerated once it exists, so hand-tuning survives — matching the same "editable,
/// generated once" contract as front/back matter (§9.2).
enum EPUBStylesheetManager {
    /// Modeled on a real finished novel's own compiled EPUB (its actual `stylesheet.css`,
    /// not a guess at one) — no forced font, justification, or hyphenation — that
    /// reference leaves all three to the reader's device/app settings, which is also
    /// friendlier to accessibility than overriding them. Paragraph indent follows the
    /// same `p + p` pattern the reference uses (indent only when a paragraph directly
    /// follows another paragraph, not just after headings/scene breaks) since it's
    /// more robust than enumerating every element a paragraph might follow. Every
    /// *other* page's heading (Contents, Dedication, About the Author — anything not
    /// specially classed below) stays deliberately plain: centered, normal weight, no
    /// border — the reference reserves the bold underlined treatment for `.chapter-title`
    /// alone, never applying it broadly to every heading the way an earlier version of
    /// this file did. Scene breaks are blank space with no glyph, matching the
    /// reference — an ornament was a guess this corrects.
    static let defaultCSS = """
        p {
          margin: 0;
          text-indent: 0;
        }

        p + p {
          text-indent: 1.5rem;
        }

        h1, h2 {
          page-break-before: always;
          margin: 2em auto 1em auto;
          text-align: center;
          font-weight: normal;
          font-size: 1.3em;
        }

        hr {
          border: none;
          margin: 2em 0;
        }

        /* Chapter headings (§ ManuscriptAssembler) — the one heading style that *is*
           bold, underlined, and boxed to its own text width, matching the reference's
           `.bordered-title`. Reserved for actual chapters — nothing else gets this.
           `margin-top` is a fixed `em` value, not a percentage — verified against a
           real render that `margin-top: %` resolves against the containing block's
           *width*, not its height (that's the CSS spec's own rule for percentage
           margins, not an EPUB quirk), so it did roughly nothing toward pushing the
           title down a reflowable page; a fixed `em` amount doesn't have that problem
           and still scales sensibly with the reader's own font-size setting.
           Scoped to `h1.chapter-title` specifically, never bare `.chapter-title` —
           pandoc puts the heading's class on its wrapping `<section>` too (verified
           against real pandoc output), so an unscoped class rule doesn't just style
           the heading, it makes every paragraph in the whole chapter inherit
           `font-weight: bold` and sit inside the same bordered box as the title. Same
           reasoning applies to `.title-page-heading` and `.hidden-heading` below. */
        h1.chapter-title {
          page-break-before: always;
          margin: 10em auto 1.5em auto;
          text-align: center;
          font-weight: bold;
          font-size: 1.3em;
          border-bottom: 2px solid currentColor;
          padding-bottom: 0.15em;
          display: table;
        }

        /* Title Page (§ FrontBackMatterTemplate.titlePage) — vertically centered on
           the page via flexbox, rather than an eyeballed top margin (§8's original
           approach), so it stays centered regardless of viewport height instead of
           being tuned for one specific window size. `section.title-page-heading`
           (not just the bare class) is deliberate — pandoc puts the heading's class
           on its wrapping `<section>` too (§ ChapterHeadingFormatter's own note on
           this), and this is the one place that's actually useful instead of a bug:
           it's the natural hook for centering the *whole* title block (heading +
           subtitle + byline), not just the heading text. */
        section.title-page-heading {
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          min-height: 90vh;
          text-align: center;
        }

        h1.title-page-heading {
          margin: 0 0 0.3em 0;
          text-align: center;
          text-transform: none;
          font-weight: normal;
          font-size: 3.5rem;
          border-bottom: none;
          padding-bottom: 0;
          display: block;
        }

        .byline {
          display: block;
          text-align: center;
          font-size: 1.75rem;
          font-style: italic;
          letter-spacing: 0.05em;
          margin-top: 1.5em;
        }

        /* Copyright (§ FrontBackMatterTemplate.copyright) — a real, linkable,
           split-able heading that's never actually shown on the page, matching a
           finished novel's own unlabeled copyright page. */
        h1.hidden-heading {
          display: none;
        }

        /* Contents (§ EPUBTableOfContentsGenerator) — plain hyperlinks, no bullets or
           numbers; `ol.toc` covers pandoc's own separately-generated nav document. */
        .toc ul, .toc ol, ol.toc {
          list-style: none;
          padding-left: 0;
          margin-left: 0;
        }

        /* Copyright, the review-ask and Newsletter back-matter pages, and the
           Dedication all read as centered blocks in a finished novel, unlike ordinary
           left-aligned/justified chapter prose — the `p + p` indent rule above is
           overridden back to 0 so a centered paragraph doesn't also pick up a stray
           first-line indent. Needs its own `margin-top` too: with its `h1` hidden
           (above), there's no longer any preceding element contributing top space,
           so content otherwise starts flush against the page edge. And since the
           indent that normally visually separated paragraphs is turned off here,
           `margin-bottom` on every paragraph takes over that job instead — without
           it, consecutive paragraphs run together with no visible break at all. */
        .centered-page {
          margin-top: 4em;
        }

        .centered-page p, .centered-page p + p {
          text-align: center;
          text-indent: 0;
          margin-bottom: 1em;
        }
        """

    /// The Short Story counterpart to `defaultCSS`: identical in every respect except
    /// the chapter heading. A short story's sections are bare numbers ("1", "2", "3" —
    /// `ManuscriptTemplate.shortStory`), not named chapters, so the bold/underlined/boxed
    /// `.chapter-title` treatment reads as over-styled for what's really just a numbered
    /// scene break. This swaps it for the same plain, centered, normal-weight look
    /// `defaultCSS` already uses for every *other* heading (Contents, Dedication, etc.),
    /// just page-broken like a chapter still is.
    static let shortStoryCSS = """
        p {
          margin: 0;
          text-indent: 0;
        }

        p + p {
          text-indent: 1.5rem;
        }

        h1, h2 {
          page-break-before: always;
          margin: 2em auto 1em auto;
          text-align: center;
          font-weight: normal;
          font-size: 1.3em;
        }

        hr {
          border: none;
          margin: 2em 0;
        }

        /* Numbered scene breaks (§ ManuscriptAssembler) — deliberately plain, unlike
           Novel's boxed/underlined `.chapter-title`: a bare "1"/"2"/"3" doesn't read as
           a titled chapter, so it gets the same treatment as every other heading rather
           than a distinct bordered style. */
        h1.chapter-title {
          page-break-before: always;
          margin: 10em auto 1.5em auto;
          text-align: center;
          font-weight: normal;
          font-size: 1.3em;
        }

        /* Title Page (§ FrontBackMatterTemplate.titlePage) — vertically centered on
           the page via flexbox, rather than an eyeballed top margin (§8's original
           approach), so it stays centered regardless of viewport height instead of
           being tuned for one specific window size. `section.title-page-heading`
           (not just the bare class) is deliberate — pandoc puts the heading's class
           on its wrapping `<section>` too, and this is the one place that's actually
           useful instead of a bug: it's the natural hook for centering the *whole*
           title block (heading + subtitle + byline), not just the heading text. */
        section.title-page-heading {
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          min-height: 90vh;
          text-align: center;
        }

        h1.title-page-heading {
          margin: 0 0 0.3em 0;
          text-align: center;
          text-transform: none;
          font-weight: normal;
          font-size: 3.5rem;
          border-bottom: none;
          padding-bottom: 0;
          display: block;
        }

        .byline {
          display: block;
          text-align: center;
          font-size: 1.75rem;
          font-style: italic;
          letter-spacing: 0.05em;
          margin-top: 1.5em;
        }

        /* Copyright (§ FrontBackMatterTemplate.copyright) — a real, linkable,
           split-able heading that's never actually shown on the page, matching a
           finished novel's own unlabeled copyright page. */
        h1.hidden-heading {
          display: none;
        }

        /* Contents (§ EPUBTableOfContentsGenerator) — plain hyperlinks, no bullets or
           numbers; `ol.toc` covers pandoc's own separately-generated nav document. */
        .toc ul, .toc ol, ol.toc {
          list-style: none;
          padding-left: 0;
          margin-left: 0;
        }

        /* Copyright, the review-ask and Newsletter back-matter pages, and the
           Dedication all read as centered blocks in a finished novel, unlike ordinary
           left-aligned/justified chapter prose — the `p + p` indent rule above is
           overridden back to 0 so a centered paragraph doesn't also pick up a stray
           first-line indent. Needs its own `margin-top` too: with its `h1` hidden
           (above), there's no longer any preceding element contributing top space,
           so content otherwise starts flush against the page edge. And since the
           indent that normally visually separated paragraphs is turned off here,
           `margin-bottom` on every paragraph takes over that job instead — without
           it, consecutive paragraphs run together with no visible break at all. */
        .centered-page {
          margin-top: 4em;
        }

        .centered-page p, .centered-page p + p {
          text-align: center;
          text-indent: 0;
          margin-bottom: 1em;
        }
        """

    /// `.novel` keeps the original `epub.css` filename so existing hand-edited files
    /// keep working untouched; `.shortStory` gets its own file so each template's
    /// "write once, then user-editable" contract stays independent of the other.
    private static func filename(for template: ManuscriptTemplate) -> String {
        switch template {
        case .novel: return "epub.css"
        case .shortStory: return "epub-short-story.css"
        }
    }

    private static func content(for template: ManuscriptTemplate) -> String {
        switch template {
        case .novel: return defaultCSS
        case .shortStory: return shortStoryCSS
        }
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Drafter", isDirectory: true)
    }

    /// Writes the template's default stylesheet only if one doesn't already exist, and
    /// returns its location either way — each template has its own file, so switching
    /// templates never touches (or loses) the other's hand-edited stylesheet.
    ///
    /// `directoryOverride` exists only for tests — it lets them target a temp directory
    /// instead of the real `~/Library/Application Support/Drafter`, which would
    /// otherwise risk clobbering a real user's hand-edited stylesheet.
    @discardableResult
    static func ensureStylesheetExists(
        template: ManuscriptTemplate,
        fileWriter: AtomicFileWriting,
        fileManager: FileManager = .default,
        directoryOverride: URL? = nil
    ) throws -> URL {
        let directory = try directoryOverride ?? applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cssURL = directory.appendingPathComponent(filename(for: template))
        if !fileManager.fileExists(atPath: cssURL.path) {
            try fileWriter.write(Data(content(for: template).utf8), to: cssURL)
        }
        return cssURL
    }
}
