import Foundation
import ProjectStore

// swiftlint:disable file_length type_body_length
// This file is dominated by one cohesive, whitespace-sensitive Typst template literal
// (`confFunction`, below) assembled from many `\(...)` interpolations threaded through
// raw Typst syntax. Splitting it into smaller pieces via string concatenation would add
// real risk of subtle formatting/interpolation bugs for a rule that doesn't reflect an
// actual maintainability concern here — it's a big data blob, not branching logic.

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
/// Scope note: implements mirrored margins/gutter, chapter openers with a drop,
/// verso/recto running heads, and front matter unnumbered with the body restarting at
/// arabic 1 (§9.4) — front/back matter headings are identified by the closed set of
/// `FrontBackMatterTemplate` anchor IDs, which survive pandoc's markdown-to-typst
/// conversion as Typst labels (`<title-page>` etc.) even though the `.hidden-heading`
/// *class* pandoc's typst writer drops entirely does not; that label match is what lets
/// this template tell "front/back matter page" apart from "body page" at all. Widow/
/// orphan suppression isn't configured explicitly — Typst's own paragraph line-breaking
/// already avoids single leftover lines by default.
///
/// Margins, body typography, chapter-opener geometry, and the scene-break glyph are
/// tuned against a real compiled print PDF (a Scrivener export of a finished novel)
/// rather than guessed — see the comments at each constant below for the measurements.
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

    // swiftlint:disable:next function_body_length
    private static func confFunction(trimSize: TrimSize, gutterInches: Double, print: ProjectMetadata.Print) -> String {
        // Read directly out of the reference's own Scrivener project file
        // (`Boyd Rook.scriv/Settings/Compile Formats/Paperback (5.06" x 7.81")
        // Copy.scrformat`, `<PageSettings><Margins>`) rather than measured/estimated
        // off the compiled PDF — the compile format spells out exact inches: Top=0.75,
        // Bottom=0.8, Left=0.75, Right=0.5. Right (outside, matching this template's
        // `outsideMargin`) confirms 0.5in was already right; Left (inside) is 0.75in =
        // outsideMargin + the base 0.25in gutter tier (`GutterCalculator`) for Rook
        // Takes' own 125-page count, confirming `insideMargin`'s formula. Top and
        // bottom were previously *eyeballed* off the compiled PDF as ~0.8in/~1.0in —
        // both wrong, and bottom especially so: the real 0.8in bottom margin is a full
        // 14.4pt (0.2in) shorter than the assumed 1.0in, which alone was enough to
        // wrongly bump content off a tightly-fit page (§ TypstDocumentGeneratorTests'
        // chapter-opener page-count regression test).
        let outsideMargin = 0.5
        let topMargin = 0.75
        let bottomMargin = 0.8
        let insideMargin = outsideMargin + gutterInches
        // Chapter numeral size, as an *absolute* point size rather than `Nem` —
        // Typst's own built-in default heading style already scales a level-1
        // heading's ambient text size to 1.4x the body size before our `show
        // heading` rule below even runs, so `size: 1.7em` inside that rule was
        // compounding onto that already-bumped ambient size (1.7 x 1.4 = 2.38x
        // body) instead of the intended 1.7x — verified directly: a bare,
        // un-styled heading at 11.5pt body rendered at 16.1pt with zero explicit
        // sizing at all, and 16.1 x 1.7 is exactly the 27.37pt this bug produced,
        // visibly bigger than the KDP reference's real chapter numeral (a
        // measured 20pt at that same 11.5pt body — this ratio, 20/11.5, is what
        // sets the multiplier below, not an arbitrarily chosen 1.7). An absolute
        // point size sidesteps Typst's ambient default entirely.
        let headingPointSize = print.bodyPointSize * (20.0 / 11.5)
        // Both read directly off the reference's own authored RTF source
        // (`Boyd Rook.scriv/Files/Data/<doc-uuid>/content.rtf` for the Title Page and
        // About the Author binder items), not measured off the compiled PDF or
        // guessed: the title itself is `\fs72` (36pt) Georgia with no `\b` anywhere in
        // its run, so it's set *regular* weight below despite reading heavy on the
        // page — Georgia's regular weight is just sturdy at display sizes, and a
        // previous version of this template wrongly bolded it chasing that look.
        // About the Author's heading is `\f0\b\fs24` (12pt) Times-Bold — barely bigger
        // than body text, not the `headingPointSize` (20pt) a chapter numeral uses.
        let titlePointSize = print.bodyPointSize * (36.0 / 11.5)
        let matterHeadingPointSize = print.bodyPointSize * (12.0 / 11.5)
        let openOnRecto = print.chapterOpensOn.lowercased() == "recto"
        let frontMatterLabels = typstLabelList(FrontBackMatterTemplate.allCases.filter { $0.section == .front })
        let backMatterLabels = typstLabelList(FrontBackMatterTemplate.allCases.filter { $0.section == .back })
        let hiddenHeadingLabels = typstLabelList(FrontBackMatterTemplate.allCases.filter { !$0.showsHeadingOnPage })

        // swiftlint:disable line_length
        return """
            // Front/back matter headings are identified by label (see the type doc
            // comment above) rather than by heading level, since chapters and matter
            // both compile to plain level-1 headings — only their `#id` survives as a
            // Typst label pandoc doesn't drop.
            #let frontMatterLabels = (\(frontMatterLabels))
            #let backMatterLabels = (\(backMatterLabels))
            // Copyright/Dedication/A Note From/Newsletter carry their own body copy
            // (legal text, a quote, ad copy) and never show their heading text on the
            // page — only Title Page and About the Author do (§ FrontBackMatterTemplate
            // .showsHeadingOnPage).
            #let hiddenHeadingLabels = (\(hiddenHeadingLabels))
            // Tracks whether *any* heading has been placed yet, so the very first one
            // (the title page, or chapter 1 if front matter is off) never gets a
            // pagebreak before it — it's already at the top of a blank page 1.
            // Checking `here().page() > 1` instead looked plausible but is wrong: a
            // short front-matter page (e.g. Copyright, a couple of lines) never
            // advances the physical page counter on its own, so the *next* heading
            // would wrongly see itself as still "page 1" and skip its own break too
            // (verified against a real compile: Title Page and Copyright landed on
            // the same page). An explicit state, not page position, is what's needed.
            #let seenHeading = state("drafter-seen-heading", false)
            // The physical page the body (the first non-front/back-matter heading)
            // starts on — `none` while still in front matter. Drives both "restart
            // numbering at arabic 1 here" and "no running head on front-matter pages".
            #let bodyStartPage = state("drafter-body-start-page", none)
            // Whether the section the *most recently placed* heading started is meant
            // to sit vertically centered on its own page (Copyright/Dedication/A Note
            // From/Newsletter — plain body copy with no heading of its own shown) —
            // read right before the *next* heading's pagebreak to close the section
            // out with a matching bottom spacer (§ the `v(1fr)` pair below).
            #let centerCurrentSection = state("drafter-center-current-section", false)

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
                margin: (inside: \(insideMargin)in, outside: \(outsideMargin)in, top: \(topMargin)in, bottom: \(bottomMargin)in),
                // Numbered manually via the footer below instead of `numbering:`'s
                // built-in string-pattern form, which can't express "unnumbered while
                // still in front matter, then restart at 1 once the body begins" —
                // that needs `bodyStartPage`'s state, only readable via `context`.
                numbering: none,
                header: context {
                  // No running head over front/back matter (title page, copyright,
                  // dedication, and the back-matter notes), and none on a chapter's own
                  // opening page either (its title already marks the page) — only
                  // non-opener body pages, matching how a running head is used in an
                  // actual printed book. Chapter-opener detection uses `query()`
                  // instead of a state read: a state set by a heading further down
                  // *this same page* isn't visible yet to this page's own header — a
                  // header is laid out relative to the top of the page, before that
                  // page's own content runs — so a state-based check only ever
                  // happened to suppress the header on the very first chapter
                  // (verified against a real compile: it wrongly still showed the
                  // header on every chapter after the first). `query()` sidesteps that
                  // ordering entirely by looking at the fully-resolved heading
                  // locations directly.
                  //
                  // Font/size/case measured directly off a real compiled reference
                  // (a Scrivener export of a finished novel): Optima 9pt, plain
                  // mixed-case — confirmed by rendering and visually inspecting the
                  // header, not assumed — not the body font at 8pt in small caps this
                  // used to render as, which is a visibly different, smaller texture.
                  if bodyStartPage.get() != none {
                    let pageNum = here().page()
                    let backMatterStarted = query(heading.where(level: 1)).any(h => {
                      let hLabel = if h.has("label") { h.label } else { none }
                      hLabel in backMatterLabels and h.location().page() <= pageNum
                    })
                    let openersOnThisPage = query(heading.where(level: 1)).filter(h => {
                      let hLabel = if h.has("label") { h.label } else { none }
                      let hIsMatter = hLabel in frontMatterLabels or hLabel in backMatterLabels
                      h.location().page() == pageNum and not hIsMatter
                    })
                    if not backMatterStarted and openersOnThisPage.len() == 0 {
                      if calc.even(pageNum) {
                        align(center)[#text(font: ("Optima",), size: 9pt)[#authorName]]
                      } else {
                        align(center)[#text(font: ("Optima",), size: 9pt)[#bookTitle]]
                      }
                    }
                  }
                },
                footer: context {
                  // Numbered only across the body itself — front matter never had a
                  // number (see the header above), and back matter drops it too once
                  // it begins, the same way front matter does. `query()` again rather
                  // than a state read, for the same reason as the header: whether
                  // *this* page is at or past the first back-matter heading needs the
                  // fully-resolved heading locations, not a same-page-timing-sensitive
                  // state value. 9pt matches the same reference's measured footer size
                  // (the body font itself was already correct here, just the size).
                  let started = bodyStartPage.get()
                  if started != none {
                    let pageNum = here().page()
                    let backMatterStartedByThisPage = query(heading.where(level: 1)).any(h => {
                      let hLabel = if h.has("label") { h.label } else { none }
                      hLabel in backMatterLabels and h.location().page() <= pageNum
                    })
                    if not backMatterStartedByThisPage {
                      align(center)[#text(size: 9pt)[#(pageNum - started + 1)]]
                    }
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
              //
              // `print.leading` (§ ProjectMetadata.Print) is the *total* desired
              // baseline-to-baseline line pitch in em (its own doc comment: "~1.46em
              // leading (16.8pt line pitch)" at 11.5pt). Typst's own `par.leading`
              // parameter is NOT that — it's extra space added *on top of* the font's
              // natural single-line height, so passing `print.leading` straight
              // through nearly doubled real line pitch (verified against a real
              // compile: a 10k-word body rendered 49 pages instead of the intended
              // ~26). A single shared "~0.68em average" subtraction (this constant's
              // previous value) was still off enough to matter: at the old flat 0.68em,
              // a real chapter-opener page compiled two lines short of the reference
              // PDF this template reproduces (a Scrivener export) — its last line lands
              // just ~4pt above the bottom margin, so even a ~0.17pt/line pitch drift
              // compounds across ~15 lines into enough overflow to bump a whole
              // paragraph onto the next page. Re-derived per font by measuring real
              // pitch off an actual compiled 26-line body page (not an isolated
              // synthetic test, which undershot by ~0.005em against font hinting/
              // rasterization in real prose) and solving `naturalHeight = observedPitch
              // - oldTypstLeadingEm * fontSize`: Palatino comes out to 0.6948em: with
              // that value, the same chapter-opener page's line pitch matches the
              // reference to within 0.03pt/line. EB Garamond was measured the isolated-
              // test way (0.6465em, not yet cross-checked against a real compile the
              // same way) — a 0.048em spread from Palatino either way, confirming a
              // single shared average was never going to fit both. Any font not
              // directly measured falls back to the old 0.68em average.
              let typstLeadingEm = calc.max(0.05, \(print.leading) - \(naturalLineHeightEm(forFont: print.bodyFont)))
              // `print.firstLineIndentEm` — a compile setting (§ CompileSheet's
              // `printFields`) — measured at ~1em off the same reference (~11.25pt at
              // 11.5pt), not the 1.2em previously guessed here.
              set par(justify: true, leading: typstLeadingEm * 1em, first-line-indent: \(print.firstLineIndentEm)em, spacing: typstLeadingEm * 1em)

              show heading.where(level: 1): it => {
                let label = if it.has("label") { it.label } else { none }
                let isMatter = label in frontMatterLabels or label in backMatterLabels
                // Only real chapters and the title page get the chapter-opener drop
                // (dropped ~30% down the page); the rest of front/back matter starts
                // flush at the top like an ordinary page — Copyright/Dedication/etc.
                // never show a heading at all (see `hiddenHeadingLabels` below), and
                // About the Author is a real section title but not a chapter opener.
                let isOpener = not isMatter or label == <title-page>
                let showsHeading = not (label in hiddenHeadingLabels)
                // Copyright reads as a normal top-flush page in the reference (its
                // first line sits right where an ordinary page's text would start),
                // not vertically centered like Dedication/A Note From/Newsletter — so
                // it's carved out of `shouldCenter` below and left to flow like any
                // other non-opener page instead.
                let isCopyright = label == <copyright>
                // Dedication/A Note From/Newsletter are plain body copy with no
                // heading shown at all — those sit vertically centered on their own
                // page, matching the `.centered-page` div the markdown wraps them in
                // (`FrontBackMatterTemplate`) — a class pandoc's typst writer drops on
                // the way over, same as the heading classes above, so it has to be
                // re-derived here from the label instead.
                let shouldCenter = isMatter and not showsHeading and not isCopyright
                context {
                  if seenHeading.get() {
                    // Closes out the *previous* section's centering, if it had any,
                    // with a matching bottom spacer before this heading's own break —
                    // `v(0.6fr)` alone at a centered section's start would push its
                    // content to the very bottom of the page instead of centering it,
                    // since nothing then claims the leftover space below. `1.4fr` here
                    // against `0.6fr` at the start (§ below) is the same top-light/
                    // bottom-heavy balance that shifts centered matter pages up from a
                    // plain 50/50 center to match the reference.
                    if centerCurrentSection.get() {
                      v(1.4fr)
                    }
                    // The recto-forced opener (§9.4's `chapterOpensOn: "recto"`) only
                    // applies to actual chapters — front/back matter always just
                    // takes the very next page, odd or even.
                    if isMatter {
                      pagebreak()
                    } else {
                      \(openOnRecto ? "pagebreak(to: \"odd\")" : "pagebreak()")
                    }
                  }
                }
                seenHeading.update(true)
                centerCurrentSection.update(shouldCenter)
                if not isMatter {
                  context {
                    if bodyStartPage.get() == none {
                      bodyStartPage.update(here().page())
                    }
                  }
                }
                if isOpener {
                  // 25.64% (not the previous 30%) — calibrated against the KDP
                  // reference this trim reproduces (§ TrimSize.fiveByEight): its
                  // Scrivener compile format drops the chapter heading by
                  // `PagePadding=8` (8 blank lines) before the title, which measured
                  // out to the heading landing at 165.5pt down a 562.32pt-tall page.
                  // Verified end to end against a real compile: this value lands the
                  // heading at 166.5pt and the first body paragraph at exactly 221.5pt
                  // — matching the reference's own measured body-start position
                  // precisely, not approximately.
                  v(25.64%)
                  // Title Page wants a bit more air above its own heading than a
                  // chapter numeral does — an extra line, on top of the shared 25.64%
                  // drop above, without changing that drop for every real chapter too.
                  if isMatter {
                    v(1em)
                  }
                  // Only real chapter numbers/titles get the dedicated heading font —
                  // measured off the same reference as Times New Roman against a
                  // Palatino body, a deliberate contrast, not a fallback. The title
                  // page's own heading is neither of those — Georgia, regular weight,
                  // at `titlePointSize` (§ above), per the reference's own authored RTF
                  // source rather than assumed or eyeballed off the rendered glyphs.
                  // `headingPointSize` (§ above) and the `pt`-not-`em` gap below both
                  // avoid Typst's ambient heading-size bug the same way.
                  if isMatter {
                    align(center)[#text(font: ("Georgia",), size: \(titlePointSize)pt, weight: "regular")[#it.body]]
                  } else {
                    align(center)[#text(font: ("\(print.headingFont)",), size: \(headingPointSize)pt, weight: "regular")[#it.body]]
                  }
                  // Not a flat `3 * bodyPointSize` — the first body paragraph's own
                  // ambient spacing-before (`typstLeadingEm`, already in scope above)
                  // stacks on top of this explicit gap rather than being absorbed by
                  // it, so the *intended* 3-line gap has to have that already-coming
                  // spacing subtracted out first, or the real gap overshoots by
                  // however much that paragraph spacing is (verified against a real
                  // compile: an un-adjusted `3 * bodyPointSize` here left the first
                  // paragraph landing ~10pt lower than the reference's own measured
                  // position).
                  v((3 - typstLeadingEm) * \(print.bodyPointSize)pt)
                  // Two more lines of air before the byline, Title Page only — the
                  // byline sits inside the centered-page block below (its own font/
                  // size handled there), this just widens the gap leading into it.
                  if isMatter {
                    v(2em)
                  }
                } else if showsHeading {
                  // Only About the Author reaches this branch (Title Page is caught by
                  // the isOpener branch above). Font is the heading font (Times New
                  // Roman by default) bold, same family as a chapter numeral — checked
                  // directly against the reference's own authored RTF source (its
                  // heading run is Times-Bold, 12pt), not assumed to match the title
                  // page just because both are bold matter headings (the title page
                  // turned out to be Georgia, a different font entirely — see the
                  // isOpener branch above). But the size is matterHeadingPointSize
                  // (12pt-at-11.5 body, see above), not headingPointSize (20pt) — that
                  // source RTF is barely bigger than body text, not a big
                  // chapter-numeral-sized display heading.
                  align(center)[#text(font: ("\(print.headingFont)",), size: \(matterHeadingPointSize)pt, weight: "bold")[#upper(it.body)]]
                  // The reference's own gap here (a 12pt paragraph-spacing value) reads
                  // as tighter on paper than the page actually shows — eyeballed larger
                  // against a real compile instead of trusting that RTF number as the
                  // final word, the same way applyCenteredMatterStyling's per-page
                  // spacing constants below are.
                  v(4 * \(print.bodyPointSize)pt)
                } else if shouldCenter {
                  // Dedication/A Note From/Newsletter sit higher on the page in the
                  // reference than a plain 50/50 vertical center — an even `v(1fr)` /
                  // `v(1fr)` split (below, at the next heading) pushed them too far
                  // down. Weighting the top spacer lighter than the bottom one shifts
                  // the balance point up without pinning it to a fixed offset that
                  // would only be right for one specific block of text.
                  v(0.6fr)
                }
              }

              doc
            }
            """
        // swiftlint:enable line_length
    }

    /// A font's real zero-leading line pitch, in em — i.e. how tall Typst renders a
    /// line of this font with no `par.leading` added at all, which is what
    /// `typstLeadingEm` above needs to subtract out of the *intended* total pitch to
    /// get the value Typst's own `leading` parameter wants. Palatino's value (0.6948em)
    /// was reverse-engineered from a real compiled 26-line body page (solving
    /// `naturalHeight = observedPitch - oldTypstLeadingEm * fontSize` against the
    /// actual measured pitch), which tracks the reference PDF's own pitch to within
    /// 0.03pt/line — an isolated `#set par(leading: 0em)` synthetic test undershot this
    /// by ~0.005em, evidently not capturing quite the same hinting/rasterization real
    /// prose gets. EB Garamond (0.6465em) is still from that synthetic method and
    /// hasn't been cross-checked the same way. Either way the two fonts differ by
    /// ~0.048em (about half a point at body size) — different enough that the single
    /// flat "~0.68em average" this used to subtract for every font left Palatino's own
    /// real line pitch running consistently taller than intended, quietly costing whole
    /// lines on any page where the target reference PDF was already tightly fit to its
    /// bottom margin. Any font without a direct measurement here keeps that old 0.68em
    /// average rather than guessing.
    private static func naturalLineHeightEm(forFont font: String) -> Double {
        switch font {
        case "Palatino": return 0.6948
        case "EB Garamond": return 0.6465
        default: return 0.68
        }
    }

    /// Renders a Typst label-array literal (`<title-page>, <copyright>`) from
    /// `FrontBackMatterTemplate` cases, so the front/back-matter label sets embedded
    /// in the template stay in sync with `FrontBackMatterTemplate.anchorID` — the
    /// single source of truth for those IDs — instead of a second hardcoded list here
    /// silently drifting out of it.
    private static func typstLabelList(_ templates: [FrontBackMatterTemplate]) -> String {
        templates.map { "<\($0.anchorID)>" }.joined(separator: ", ")
    }

    /// Copyright/Dedication/A Note From/Newsletter's body copy needs real horizontal
    /// centering and actual paragraph spacing (a plain document look, not the
    /// seamless novel-body flow chapters use) — the markdown wraps them in a
    /// `::: {.centered-page}` div for exactly that, but pandoc's typst writer only
    /// preserves the div as a bare `#block[...]`, dropping the class along with any
    /// styling it implied (same loss as the heading classes elsewhere in this file).
    ///
    /// This can't be fixed from inside `conf`'s `show heading` rule the way the
    /// vertical centering above is: `set par(justify:/first-line-indent:/spacing:)`
    /// only affects how a paragraph's *own* line-breaking happens, which is fixed at
    /// the point that paragraph is first encountered in the document — a later `set`
    /// reached via `show par: it => context { set par(...); it }` does not
    /// retroactively re-break `it` (verified directly: text kept rendering fully
    /// justified/indented regardless). `set align(...)` on its own *does* work that
    /// way, but centering only the not-fully-justified last line of a paragraph and
    /// nowhere else looks broken, not centered.
    ///
    /// What actually works (verified against a real compile) is a `set` sitting
    /// directly, unwrapped, inside the very block the paragraphs are already inside —
    /// which pandoc has conveniently already emitted as `#block[...]` right after each
    /// of these labels. So instead of fighting that from the template, this appends
    /// the two `set` lines directly inside that specific block, string-matched by the
    /// label pandoc places right before it (`<copyright>`, `<dedication>`, etc.) —
    /// the same anchor-label mechanism `conf`'s own `show heading` rule uses to tell
    /// these pages apart, applied here as a post-pass the same way
    /// `applySceneBreakOrnament` below already patches pandoc's raw .typ output.
    public static func applyCenteredMatterStyling(to typstSource: String, bodyPointSize: Double) -> String {
        // Title Page's own byline ("Drew Calloway") is wrapped in the same
        // `::: {.centered-page}` div as Copyright/Dedication/etc — it needs the same
        // horizontal centering (it was rendering flush-left before), even though its
        // heading goes through the `isOpener` branch in `conf` rather than
        // `shouldCenter`. Only About the Author is excluded: its body is ordinary
        // block prose, not a `.centered-page` div, so pandoc never emits a `#block[`
        // right after its label for this to match against.
        (FrontBackMatterTemplate.allCases.filter { !$0.showsHeadingOnPage } + [.titlePage])
            .reduce(typstSource) { source, template in
                let anchor = "<\(template.anchorID)>\n#block[\n"
                // Copyright's font size (9pt) and paragraph gaps come straight from
                // the reference's own authored RTF source
                // (`Boyd Rook.scriv/Files/Data/21506607.../content.rtf`): `\fs18` is a
                // literal 9pt, not `bodyPointSize`-relative, and the gap between its
                // three blocks (the fiction disclaimer, the copyright line, and the
                // rights-reserved paragraph) is a genuine blank paragraph in that
                // source — an actual empty line, each carrying its own `\sa240`
                // (12pt) spacing-after on top of its own line height — not just one
                // ordinary paragraph gap. `spacing: 3.8em` at 9pt (~34pt) approximates
                // that blank-line-plus-spacing total; a real compile still read short
                // of it, so this was bumped up again from an earlier 2.4em rather than
                // trusting the RTF numbers as the final word.
                let extraRules: String
                switch template {
                case .copyright:
                    extraRules = "#set text(size: 9pt)\n"
                        + "#set par(justify: false, first-line-indent: 0em, spacing: 3.8em)\n"
                case .reviewAsk, .newsletter:
                    // The gap between the bold question and the body paragraph read as
                    // a full extra blank line short against the reference — bumped
                    // further than Dedication/Title Page's shared 2.2em rather than
                    // raising that default for every centered page alike. Widened again
                    // (3.6em -> 4.6em) after a real compile still read one line short.
                    extraRules = "#set par(justify: false, first-line-indent: 0em, spacing: 4.6em)\n"
                case .titlePage:
                    // The byline is Georgia too in the reference's own RTF source, not
                    // the Palatino body font it was silently inheriting here — `\fs42`
                    // (21pt), same family as the title itself just smaller.
                    extraRules = "#set text(font: (\"Georgia\",), size: \(bodyPointSize * (21.0 / 11.5))pt)\n"
                        + "#set par(justify: false, first-line-indent: 0em, spacing: 2.2em)\n"
                default:
                    extraRules = "#set par(justify: false, first-line-indent: 0em, spacing: 2.2em)\n"
                }
                // `width: 100%` matters, not just cosmetic: a plain `#block[...]`
                // shrinks to fit its own content, so `#set align(center)` inside it is
                // a no-op whenever the block holds only a single short line (verified
                // directly — Title Page's one-line byline stayed flush left with
                // `align(center)` set and no explicit width, while Copyright/
                // Dedication's multi-line wrapped paragraphs happened to center fine
                // regardless, because line-wrapping alone already stretched their box
                // to the full available width). Forcing the width removes that
                // content-dependent coincidence for every centered block alike.
                let styled = "<\(template.anchorID)>\n#block(width: 100%)[\n"
                    + "#set align(center)\n"
                    + extraRules
                return source.replacingOccurrences(of: anchor, with: styled)
            }
    }

    /// The paragraph right after a chapter heading is flush left, not indented like
    /// every other paragraph — measured directly off the same reference (its first
    /// line sits at the same x-position as every continuation line, unlike every
    /// other first line, which is indented). Chapters aren't wrapped in a `#block[...]`
    /// the way front/back matter is (§ `applyCenteredMatterStyling`), so there's no
    /// block to inject a scoped `set` into — instead this locates each chapter
    /// heading's label (any label that *isn't* one of `FrontBackMatterTemplate`'s six)
    /// and its immediately-following paragraph (pandoc emits a whole paragraph as one
    /// unbroken line in the .typ source — actual line-wrapping happens later, at typst
    /// compile time), and brackets just that paragraph with a `0em` indent followed by
    /// a reset back to the real one for everything after it. This is the same
    /// unwrapped-`set`-in-source-text approach as `applyCenteredMatterStyling`, for the
    /// same reason: a later `set par(first-line-indent:)` reached through a heading's
    /// own `show` rule doesn't retroactively re-break a paragraph that already exists
    /// (verified directly — the indent kept applying regardless).
    public static func applyFlushFirstParagraphAfterChapterHeadings(
        to typstSource: String, firstLineIndentEm: Double
    ) -> String {
        // About the Author's own first paragraph ("Drew Calloway writes...") is flush
        // left in the reference too, same as a chapter's opening paragraph — its body
        // is ordinary block prose (§ `applyCenteredMatterStyling`'s doc comment), not a
        // `.centered-page` div, so it needs this same regex-based flush rather than the
        // block-scoped `set` the centered pages get. Excluding it from `matterAnchors`
        // below is what lets it fall through to the same pattern chapters use.
        let matterAnchors = FrontBackMatterTemplate.allCases
            .filter { $0 != .aboutTheAuthor }
            .map(\.anchorID).joined(separator: "|")
        // A paragraph doesn't necessarily land on one unbroken source line — pandoc
        // wraps long ones across several lines with plain single `\n`s between them
        // (verified against a real compile: an early version of this pattern matched
        // only the paragraph's first wrapped line, leaving the rest of it — and the
        // reset for the paragraph after — untouched). `.dotMatchesLineSeparators`
        // plus a non-greedy `.+?` matches the whole paragraph up to the first real
        // blank line, wrapped or not. The terminator itself is `\n\n` *or* end of
        // string — whichever heading happens to be last in the whole assembled
        // document (About the Author, ordinarily) has no blank line after its
        // paragraph at all, just EOF, and requiring `\n\n` unconditionally silently
        // skipped flushing that one paragraph every time (caught by rendering a real
        // full-book compile and finding About the Author's opening line still
        // indented, unlike every other chapter/section it's meant to match).
        let pattern = "<(?!(?:\(matterAnchors))>)([a-zA-Z0-9-]+)>\n(.+?)(?:\n\n|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return typstSource
        }
        let range = NSRange(typstSource.startIndex..., in: typstSource)
        let template = "<$1>\n#set par(first-line-indent: 0em)\n$2\n\n"
            + "#set par(first-line-indent: \(firstLineIndentEm)em)\n\n"
        return regex.stringByReplacingMatches(in: typstSource, range: range, withTemplate: template)
    }

    /// pandoc's own default template polyfills `#divider()` as a plain horizontal
    /// line, and our inlined `conf` function has no way to override it (`divider` is
    /// defined earlier in the template, outside `conf`'s scope) — so instead of
    /// fighting that, the scene-break ornament (§9.4) is substituted after pandoc
    /// runs, on the generated .typ text directly.
    public static func applySceneBreakOrnament(to typstSource: String) -> String {
        // `*` is typst markup syntax for strong emphasis, not a literal character —
        // `[* * *]` parses as an opening `*`, then a second `*` immediately closing it
        // (leaving a lone space as the "strong" content), then a dangling unclosed
        // `*`, which typst rejects outright as a syntax error. Escaping each asterisk
        // (`\*`) is what actually renders three literal asterisks.
        typstSource.replacingOccurrences(
            of: "#divider()",
            with: "#align(center)[\\* \\* \\*]"
        )
    }
}
// swiftlint:enable file_length type_body_length
