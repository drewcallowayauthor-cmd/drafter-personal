import Foundation
import ProjectStore

/// Generates the full custom Typst template (§9.4) passed to pandoc's `--template`.
///
/// Discovered by directly compiling test documents rather than guessing at the API:
/// pandoc's own default template supports importing a `conf` function from a separate
/// file via a `template` *metadata* variable (`#import "$template$": conf`) — but that
/// metadata value goes through markdown inline parsing before being substituted, which
/// silently escapes underscores in the path (`_` → `\_`, markdown's italics escape),
/// breaking on any path containing one — a temp directory, a username, a project name.
/// Verified this failure directly, then verified the fix: `--template` replaces
/// pandoc's whole document wrapper, so this embeds pandoc's own default template text
/// (`pandoc --print-default-template=typst`) with our `conf` function inlined in place
/// of the import, avoiding any external file path substitution entirely. Re-verified
/// end to end against a path deliberately containing an underscore.
///
/// Scope note: implements mirrored margins/gutter, chapter openers starting on recto
/// with a drop, verso/recto running heads, and continuous page numbering. §9.4 also
/// specifies front matter using roman numerals with the body restarting at arabic 1;
/// that needs a machine-readable marker at the front-matter/body boundary in the
/// assembled markdown (via a raw ```{=typst}``` block) that this generator alone can't
/// provide, so v1 uses one continuous numbering scheme — flagged here rather than
/// silently dropped, the same way §9.3's epub.css is flagged as needing tuning.
/// Widow/orphan suppression isn't configured explicitly — Typst's own paragraph
/// line-breaking already avoids single leftover lines by default.
public enum TypstDocumentGenerator {
    /// The exact marker pandoc's default template (as of pandoc 3.10.2) uses to import
    /// `conf` — replaced wholesale with our inlined function definition.
    private static let importMarker = """
        $if(template)$
        #import "$template$": conf
        $else$
        $template.typst()$
        $endif$
        """

    public static func fullTemplate(
        pandocDefaultTemplate: String,
        trimSize: TrimSize,
        gutterInches: Double,
        print: ProjectMetadata.Print
    ) -> String {
        pandocDefaultTemplate.replacingOccurrences(
            of: importMarker,
            with: confFunction(trimSize: trimSize, gutterInches: gutterInches, print: print)
        )
    }

    private static func confFunction(trimSize: TrimSize, gutterInches: Double, print: ProjectMetadata.Print) -> String {
        let outsideMargin = 0.625
        let insideMargin = outsideMargin + gutterInches
        let openOnRecto = print.chapterOpensOn.lowercased() == "recto"

        return """
            #let conf(
              title: none,
              subtitle: none,
              authors: (),
              keywords: (),
              date: none,
              lang: "en",
              region: none,
              abstract-title: none,
              abstract: none,
              thanks: none,
              margin: (x: 1in, y: 1in),
              paper: "us-letter",
              font: (),
              fontsize: 11pt,
              mathfont: (),
              codefont: (),
              linestretch: 1,
              sectionnumbering: none,
              pagenumbering: none,
              linkcolor: none,
              citecolor: none,
              filecolor: none,
              cols: 1,
              doc,
            ) = {
              let authorName = if authors.len() > 0 { authors.at(0).name } else { "" }
              let bookTitle = if title != none { title } else { "" }

              set page(
                width: \(trimSize.widthInches)in,
                height: \(trimSize.heightInches)in,
                margin: (inside: \(insideMargin)in, outside: \(outsideMargin)in, top: \(outsideMargin)in, bottom: \(outsideMargin)in),
                numbering: "1",
                header: context {
                  let pageNum = counter(page).get().at(0)
                  if calc.even(pageNum) {
                    align(center)[#text(size: 8pt, tracking: 0.1em)[#smallcaps(authorName)]]
                  } else {
                    align(center)[#text(size: 8pt, tracking: 0.1em)[#smallcaps(bookTitle)]]
                  }
                },
              )

              set text(font: ("\(print.bodyFont)",), size: \(print.bodyPointSize)pt, lang: lang)
              // §9.4's "no inter-paragraph space" means no *extra* blank-line gap
              // beyond normal line spacing, not literally zero — spacing: 0em collapsed
              // the gap between one paragraph's last line and the next paragraph's
              // first line below the font's natural ascent/descent clearance, causing
              // real glyph overlap (caught by rendering an actual test PDF and looking
              // at it, not just checking that it compiled). Matching spacing to leading
              // keeps paragraph breaks visually seamless with in-paragraph line spacing.
              set par(justify: true, leading: \(print.leading)em, first-line-indent: 1.2em, spacing: \(print.leading)em)

              show heading.where(level: 1): it => {
                \(openOnRecto ? "pagebreak(to: \"odd\")" : "pagebreak()")
                v(30%)
                align(center)[#text(size: 1.4em, weight: "regular")[#it.body]]
                v(2em)
              }

              doc
            }
            """
    }

    /// pandoc's own default template polyfills `#divider()` as a plain horizontal
    /// line, and our inlined `conf` function has no way to override it (`divider` is
    /// defined earlier in the template, outside `conf`'s scope) — so instead of
    /// fighting that, the scene-break ornament (§9.4) is substituted after pandoc
    /// runs, on the generated .typ text directly.
    public static func applySceneBreakOrnament(to typstSource: String) -> String {
        typstSource.replacingOccurrences(
            of: "#divider()",
            with: "#align(center)[#v(1.5em)#text(size: 0.9em, tracking: 0.3em)[• • •]#v(1.5em)]"
        )
    }
}
