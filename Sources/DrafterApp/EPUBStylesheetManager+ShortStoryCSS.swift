import Foundation

/// `EPUBStylesheetManager.shortStoryCSS`, split into its own file to keep the enum's
/// type body under SwiftLint's length limit.
extension EPUBStylesheetManager {
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

        h1 {
          page-break-before: always;
          margin: 2em auto 1em auto;
          text-align: center;
          font-weight: normal;
          font-size: 1.3em;
        }

        /* Numbered scene breaks (§ ManuscriptAssembler.assembleShortStoryManuscript) —
           the whole story is one continuous EPUB section (never split into a file per
           chapter the way Novel is), so these `h2`s are plain in-line markers, not page
           breaks: matches the reference EPUB's own `.section-number` rule exactly
           (Sunrise At Sundown's real, unedited `stylesheet.css`) — spacing only, no
           `page-break-before`. Deliberately its own rule, not folded into `h1` above:
           `h1` there is real chapter-file boundaries (Title Page, Contents, etc., each
           already its own EPUB spine file), where a forced page break is redundant but
           harmless; `h2` here is the one place a forced break would be wrong, since it
           would insert a page turn *inside* what's meant to read as one flowing story. */
        h2 {
          margin: 2em auto 1.33em auto;
          text-align: center;
          font-weight: normal;
          font-size: 1.3em;
        }

        hr {
          border: none;
          margin: 2em 0;
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

        /* Dedication/epigraph (§ FrontBackMatterTemplate.dedication) — a few more
           lines down the page than Copyright's block of legal text, which shares
           `.centered-page`'s base 4em top margin. Same specificity as `.centered-page`
           above, so source order (this rule comes after) is what makes it win. */
        .dedication-page {
          margin-top: 7em;
        }

        /* The review-ask and Newsletter back-matter pages' bold opening line (§
           FrontBackMatterTemplate) — a nested fenced div, not just a class on the
           paragraph, so it gets its own `margin-bottom` distinct from `.centered-page
           p`'s standard 1em: an extra blank line between the headline and the body
           text it introduces. Same specificity as `.centered-page p` above, so source
           order (this rule comes after) is what makes it win. */
        .callout-heading p {
          margin-bottom: 2em;
        }
        """
}
