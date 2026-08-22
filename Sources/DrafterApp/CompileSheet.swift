import AppKit
import CompileService
import DrafterCore
import ProjectStore
import SwiftUI

/// Which format the compile sheet is currently set to produce.
enum CompileTarget: String, CaseIterable, Identifiable {
    case epub = "EPUB"
    case printPDF = "Print PDF"
    case docx = "Standard Manuscript Format"

    var id: String { rawValue }
}

/// A minimal, target-agnostic result the three export coordinators all reduce to, so
/// the sheet and its caller don't need to know which one actually ran.
struct CompileOutcome: Equatable {
    let outputURL: URL
}

/// §9.6's compile sheet. Front/back matter toggles, chapter title format, and scene
/// separator default from the project's saved compile settings but are export-run
/// scoped here, not written back to project.json; only "Project Settings…" does that.
///
/// Built without `NocturneSheet` (unlike the app's other sheets) because the word-count
/// estimate row is spec'd to stay pinned below the scrollable body rather than scroll
/// away with it — the same reason the pre-redesign version kept `statusBanner` outside
/// the `Form`.
struct CompileSheet: View {
    let metadata: ProjectMetadata
    let binderTree: BinderTree
    let workingTree: URL
    let onCancel: () -> Void
    /// Called on success right before the sheet closes itself — the parent shows the
    /// result as a separate alert from the main window rather than this sheet showing
    /// it inline, so it stays visible (and unmistakable) after this view is gone.
    let onCompiled: (CompileOutcome) -> Void

    @State private var target: CompileTarget = .epub
    @State private var epubTemplate: ManuscriptTemplate = .novel
    @State private var outputDirectory: URL
    @State private var chapterTitleFormat: String
    @State private var sceneSeparator: String
    @State private var includeFrontMatter: Bool
    @State private var includeBackMatter: Bool
    @State private var trimSize: TrimSize
    @State private var bodyFont: String
    @State private var bodyPointSize: Double
    @State private var firstLineIndentEm: Double
    @State private var headingFont: String
    @State private var manuscriptFont: String
    @State private var isOutputPickerPresented = false
    @State private var isCompiling = false
    @State private var compileError: String?
    @State private var wordCountEstimate = 0

    init(
        metadata: ProjectMetadata,
        binderTree: BinderTree,
        workingTree: URL,
        onCancel: @escaping () -> Void,
        onCompiled: @escaping (CompileOutcome) -> Void
    ) {
        self.metadata = metadata
        self.binderTree = binderTree
        self.workingTree = workingTree
        self.onCancel = onCancel
        self.onCompiled = onCompiled
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        _outputDirectory = State(initialValue: desktop ?? FileManager.default.homeDirectoryForCurrentUser)
        _epubTemplate = State(initialValue: ManuscriptTemplate.allCases.first {
            $0.defaultChapterTitleFormat == metadata.compile.chapterTitleFormat
        } ?? .novel)
        _chapterTitleFormat = State(initialValue: metadata.compile.chapterTitleFormat)
        _sceneSeparator = State(initialValue: metadata.compile.sceneSeparator)
        _includeFrontMatter = State(initialValue: metadata.compile.includeFrontMatter)
        _includeBackMatter = State(initialValue: metadata.compile.includeBackMatter)
        _trimSize = State(initialValue: TrimSize(rawValue: metadata.print.trimSize) ?? .fiveByEight)
        _bodyFont = State(initialValue: metadata.print.bodyFont)
        _bodyPointSize = State(initialValue: metadata.print.bodyPointSize)
        _firstLineIndentEm = State(initialValue: metadata.print.firstLineIndentEm)
        _headingFont = State(initialValue: metadata.print.headingFont)
        _manuscriptFont = State(initialValue: metadata.manuscript.bodyFont)
    }

    private var firstHeadingPreview: String {
        let firstChapterTitle = binderTree.manuscript.first?.displayName ?? "Chapter Title"
        return ChapterHeadingFormatter.heading(format: chapterTitleFormat, index: 1, title: firstChapterTitle)
            ?? "(no heading)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    targetPicker
                    outputLocationRow
                    if target != .docx {
                        frontBackMatterToggles
                    }
                    chapterFields
                    if target == .epub {
                        epubFields
                    }
                    if target == .printPDF {
                        printFields
                    }
                    if target == .docx {
                        docxFields
                    }
                }
                .padding(18)
            }
            wordCountRow
            statusBanner
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.nocturneSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Compile") { Task { await compile() } }
                    .buttonStyle(.nocturnePrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCompiling)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
        .background(Theme.Color.surface)
        .fileImporter(isPresented: $isOutputPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                outputDirectory = url
            }
        }
        .task {
            wordCountEstimate = (
                try? WordCountAggregator.aggregate(binderTree: binderTree) { try String(contentsOf: $0, encoding: .utf8) }
            )?.project ?? 0
        }
    }

    private var header: some View {
        HStack {
            Text("Compile")
                .font(Theme.Font.heading(17))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.nocturneIcon)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var targetPicker: some View {
        NocturneSegmentedControl(selection: $target, options: CompileTarget.allCases) { target in
            Text(target.rawValue)
        }
    }

    private var outputLocationRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Output Location")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            HStack {
                Text(outputDirectory.path)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { isOutputPickerPresented = true }
                    .buttonStyle(.nocturneSecondary)
            }
        }
    }

    private var frontBackMatterToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include Front Matter", isOn: $includeFrontMatter)
            Toggle("Include Back Matter", isOn: $includeBackMatter)
        }
        .tint(Theme.Color.accent)
        .foregroundStyle(Theme.Color.text)
        .font(Theme.Font.body(14))
    }

    private var chapterFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            NocturneField(label: "Chapter Title Format", text: $chapterTitleFormat)
            Text("Preview: \(firstHeadingPreview)")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            NocturneField(label: "Scene Separator", text: $sceneSeparator)
        }
    }

    private var epubFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            NocturneSegmentedControl(selection: $epubTemplate, options: ManuscriptTemplate.allCases) { template in
                Text(template.rawValue)
            }
        }
        .onChange(of: epubTemplate) { oldTemplate, newTemplate in
            // The picker only swaps EPUB CSS; "Chapter Title Format" is a separate free-text
            // field seeded from the project's saved settings, so switching templates here
            // silently left short-story exports still reading "Chapter 1" instead of "1".
            // Only follow the switch if the field still holds a template default the writer
            // hasn't customized — an edited format is left alone either way.
            if chapterTitleFormat == oldTemplate.defaultChapterTitleFormat {
                chapterTitleFormat = newTemplate.defaultChapterTitleFormat
            }
        }
    }

    private var printFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trim Size")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.text.opacity(0.7))
            NocturneSegmentedControl(selection: $trimSize, options: TrimSize.allCases) { size in
                Text("\(size.widthInches, specifier: "%g")\" × \(size.heightInches, specifier: "%g")\"")
            }
            NocturneDropdown(label: "Body Font", selection: $bodyFont, options: fontOptions) { $0 }
            NocturneDropdown(label: "Point Size", selection: $bodyPointSize, options: pointSizeOptions) {
                String(format: "%g", $0)
            }
            NocturneDropdown(label: "First-Line Indent", selection: $firstLineIndentEm, options: indentOptions) {
                String(format: "%gem", $0)
            }
            NocturneDropdown(label: "Heading Font", selection: $headingFont, options: headingFontOptions) { $0 }
        }
    }

    private var docxFields: some View {
        NocturneDropdown(label: "Manuscript Font", selection: $manuscriptFont, options: ["Times New Roman", "Courier New"]) { $0 }
    }

    /// KDP's recommended body-text serif fonts (Palatino is also `Print`'s own
    /// default, §4.5), kept to whichever are actually installed on this Mac — except
    /// EB Garamond, which the app bundles itself (`BundledFonts`) and so is always
    /// available. Centaur and Hightower Text are commercial and can't be bundled;
    /// they only appear here if already installed. The project's saved font is
    /// always included even if it's since become unavailable, so switching targets
    /// never silently discards it.
    private var fontOptions: [String] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let curated = ["Palatino", "Centaur", "Hightower Text"].filter { installed.contains($0) }
        var options = curated + [BundledFonts.ebGaramondFamily]
        if !options.contains(bodyFont) { options.append(bodyFont) }
        return options.sorted()
    }

    private var pointSizeOptions: [Double] {
        let curated: [Double] = [9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14]
        return curated.contains(bodyPointSize) ? curated : (curated + [bodyPointSize]).sorted()
    }

    /// 1em is `Print`'s own default (§ ProjectMetadata.Print), measured off a real
    /// reference; the rest span the range other manuscript/print conventions actually
    /// use, from a tight 0.75em up to the SMF-style 1.5em (matching Standard
    /// Manuscript Format's own 0.5in-at-12pt indent).
    private var indentOptions: [Double] {
        let curated: [Double] = [0.75, 1.0, 1.2, 1.5]
        return curated.contains(firstLineIndentEm) ? curated : (curated + [firstLineIndentEm]).sorted()
    }

    /// Times New Roman is `Print`'s own default (measured off the same reference as
    /// the indent above — a deliberate contrast against a Palatino/serif body, not a
    /// fallback); Georgia and Helvetica round out common heading choices. The body
    /// font itself is always offered too, for a project that wants the heading to
    /// just match — and the project's saved choice stays included even if it's since
    /// become unavailable, so switching targets never silently discards it.
    private var headingFontOptions: [String] {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let curated = ["Times New Roman", "Georgia", "Helvetica"].filter { installed.contains($0) }
        var options = curated + [bodyFont]
        if !options.contains(headingFont) { options.append(headingFont) }
        return Array(Set(options)).sorted()
    }

    /// Deliberately outside the scrollable body: a small manuscript compiles almost
    /// instantly, and burying the estimate in a trailing scrollable section gave no
    /// visible cue anything had happened at all.
    private var wordCountRow: some View {
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
    private var wordAndPageEstimateText: String {
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
    private var statusBanner: some View {
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

    private func compile() async {
        isCompiling = true
        compileError = nil
        defer { isCompiling = false }

        let pandocOverride = AppPreferences.shared.pandocPathOverride.map { URL(fileURLWithPath: $0) }
        guard let pandocURL = BinaryResolver.resolve(name: "pandoc", override: pandocOverride, bundled: BundledBinaries.pandocURL) else {
            compileError = "pandoc isn't installed or couldn't be found (checked the app's own bundled copy — "
                + "arm64 Macs only — plus ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, and PATH)."
            return
        }

        var exportMetadata = metadata
        exportMetadata.compile.chapterTitleFormat = chapterTitleFormat
        exportMetadata.compile.sceneSeparator = sceneSeparator
        exportMetadata.compile.includeFrontMatter = includeFrontMatter
        exportMetadata.compile.includeBackMatter = includeBackMatter
        exportMetadata.print.trimSize = trimSize.rawValue
        exportMetadata.print.bodyFont = bodyFont
        exportMetadata.print.bodyPointSize = bodyPointSize
        exportMetadata.print.firstLineIndentEm = firstLineIndentEm
        exportMetadata.print.headingFont = headingFont
        exportMetadata.manuscript.bodyFont = manuscriptFont

        do {
            let outcome: CompileOutcome
            switch target {
            case .epub:
                let cssURL = try EPUBStylesheetManager.ensureStylesheetExists(
                    template: epubTemplate,
                    fileWriter: LiveAtomicFileWriter()
                )
                let coordinator = EPUBExportCoordinator(processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter())
                let result = try await coordinator.export(
                    metadata: exportMetadata,
                    binderTree: binderTree,
                    workingTree: workingTree,
                    outputDirectory: outputDirectory,
                    pandocExecutableURL: pandocURL,
                    cssURL: cssURL,
                    epubTemplate: epubTemplate
                )
                outcome = CompileOutcome(outputURL: result.outputURL)

            case .printPDF:
                let typstOverride = AppPreferences.shared.typstPathOverride.map { URL(fileURLWithPath: $0) }
                guard let typstURL = BinaryResolver.resolve(name: "typst", override: typstOverride, bundled: BundledBinaries.typstURL) else {
                    compileError = "typst isn't installed or couldn't be found (checked the app's own bundled copy — "
                        + "arm64 Macs only — plus ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, and PATH)."
                    return
                }
                let coordinator = PrintExportCoordinator(processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter())
                let result = try await coordinator.export(
                    metadata: exportMetadata,
                    binderTree: binderTree,
                    workingTree: workingTree,
                    outputDirectory: outputDirectory,
                    pandocExecutableURL: pandocURL,
                    typstExecutableURL: typstURL,
                    trimSize: trimSize,
                    fontDirectoryURLs: BundledFonts.fontsDirectoryURL.map { [$0] } ?? []
                )
                outcome = CompileOutcome(outputURL: result.outputURL)

            case .docx:
                let coordinator = DOCXExportCoordinator(processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter())
                let result = try await coordinator.export(
                    metadata: exportMetadata,
                    binderTree: binderTree,
                    workingTree: workingTree,
                    outputDirectory: outputDirectory,
                    pandocExecutableURL: pandocURL
                )
                outcome = CompileOutcome(outputURL: result.outputURL)
            }

            onCompiled(outcome)
            onCancel()
        } catch {
            compileError = error.localizedDescription
        }
    }
}
