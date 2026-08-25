import AppKit
import CompileService
import DrafterCore
import SwiftUI

/// Font/estimate helpers for `CompileSheet`, split out to keep the main file's
/// type body under SwiftLint's length limit.
extension CompileSheet {
    /// KDP's recommended body-text serif fonts (Palatino is also `Print`'s own
    /// default, §4.5), kept to whichever are actually installed on this Mac — except
    /// EB Garamond, which the app bundles itself (`BundledFonts`) and so is always
    /// available. Centaur and Hightower Text are commercial and can't be bundled;
    /// they only appear here if already installed. The project's saved font is
    /// always included even if it's since become unavailable, so switching targets
    /// never silently discards it.
    var fontOptions: [String] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let curated = ["Palatino", "Centaur", "Hightower Text"].filter { installed.contains($0) }
        var options = curated + [BundledFonts.ebGaramondFamily]
        if !options.contains(bodyFont) { options.append(bodyFont) }
        return options.sorted()
    }

    var pointSizeOptions: [Double] {
        let curated: [Double] = [9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14]
        return curated.contains(bodyPointSize) ? curated : (curated + [bodyPointSize]).sorted()
    }

    /// 1em is `Print`'s own default (§ ProjectMetadata.Print), measured off a real
    /// reference; the rest span the range other manuscript/print conventions actually
    /// use, from a tight 0.75em up to the SMF-style 1.5em (matching Standard
    /// Manuscript Format's own 0.5in-at-12pt indent).
    var indentOptions: [Double] {
        let curated: [Double] = [0.75, 1.0, 1.2, 1.5]
        return curated.contains(firstLineIndentEm) ? curated : (curated + [firstLineIndentEm]).sorted()
    }

    /// Times New Roman is `Print`'s own default (measured off the same reference as
    /// the indent above — a deliberate contrast against a Palatino/serif body, not a
    /// fallback); Georgia and Helvetica round out common heading choices. The body
    /// font itself is always offered too, for a project that wants the heading to
    /// just match — and the project's saved choice stays included even if it's since
    /// become unavailable, so switching targets never silently discards it.
    var headingFontOptions: [String] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let curated = ["Times New Roman", "Georgia", "Helvetica"].filter { installed.contains($0) }
        var options = curated + [bodyFont]
        if !options.contains(headingFont) { options.append(headingFont) }
        return Array(Set(options)).sorted()
    }

    /// Deliberately outside the scrollable body: a small manuscript compiles almost
    /// instantly, and burying the estimate in a trailing scrollable section gave no
    /// visible cue anything had happened at all.
    var wordCountRow: some View {
        HStack {
            Text(wordAndPageEstimateText)
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// Print's page count is a rough pre-compile approximation (the real count only
    /// comes out of `PrintExportCoordinator`'s actual two-pass typst compile); DOCX's
    /// is the 250-words-per-page manuscript-page convention. EPUB pagination is
    /// reader-dependent, so no estimate is shown for it.
    var wordAndPageEstimateText: String {
        switch target {
        case .printPDF:
            let pages = PageEstimator.printPages(
                wordCount: wordCountEstimate,
                trimSize: trimSize,
                pointSize: bodyPointSize,
                leading: metadata.print.leading
            )
            return "\(wordCountEstimate) words · ~\(pages) pages"
        case .docx:
            let pages = PageEstimator.manuscriptPages(wordCount: wordCountEstimate)
            return "\(wordCountEstimate) words · ~\(pages) manuscript pages"
        case .epub:
            return "\(wordCountEstimate) words"
        }
    }

    @ViewBuilder
    var statusBanner: some View {
        if isCompiling {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Compiling…")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.Color.accent.opacity(0.12))
        } else if let compileError {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Compile Failed").bold().foregroundStyle(Theme.Color.text)
                }
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(compileError)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.Color.textMuted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
                .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.red.opacity(0.12))
        }
    }
}
