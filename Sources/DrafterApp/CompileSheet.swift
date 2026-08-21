import AppKit
import CompileService
import DrafterCore
import ProjectStore
import SwiftUI

/// Which format the compile sheet is currently set to produce.
enum CompileTarget: String, CaseIterable, Identifiable {
    case epub = "EPUB"
    case printPDF = "Print PDF"
    case docx = "DOCX"

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
    @State private var outputDirectory: URL
    @State private var chapterTitleFormat: String
    @State private var sceneSeparator: String
    @State private var includeFrontMatter: Bool
    @State private var includeBackMatter: Bool
    @State private var trimSize: TrimSize
    @State private var bodyFont: String
    @State private var bodyPointSize: Double
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
        _chapterTitleFormat = State(initialValue: metadata.compile.chapterTitleFormat)
        _sceneSeparator = State(initialValue: metadata.compile.sceneSeparator)
        _includeFrontMatter = State(initialValue: metadata.compile.includeFrontMatter)
        _includeBackMatter = State(initialValue: metadata.compile.includeBackMatter)
        _trimSize = State(initialValue: TrimSize(rawValue: metadata.print.trimSize) ?? .fiveByEight)
        _bodyFont = State(initialValue: metadata.print.bodyFont)
        _bodyPointSize = State(initialValue: metadata.print.bodyPointSize)
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
                    frontBackMatterToggles
                    chapterFields
                    if target == .printPDF {
                        printFields
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
        }
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

    /// Deliberately outside the scrollable body: a small manuscript compiles almost
    /// instantly, and burying the estimate in a trailing scrollable section gave no
    /// visible cue anything had happened at all.
    private var wordCountRow: some View {
        HStack {
            Text("\(wordCountEstimate) words")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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

        guard let pandocURL = BinaryResolver.resolve(name: "pandoc") else {
            compileError = "pandoc isn't installed or couldn't be found (checked ~/.local/bin, /opt/homebrew/bin, "
                + "/usr/local/bin, and PATH)."
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

        do {
            let outcome: CompileOutcome
            switch target {
            case .epub:
                let cssURL = try EPUBStylesheetManager.ensureStylesheetExists(fileWriter: LiveAtomicFileWriter())
                let coordinator = EPUBExportCoordinator(processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter())
                let result = try await coordinator.export(
                    metadata: exportMetadata,
                    binderTree: binderTree,
                    workingTree: workingTree,
                    outputDirectory: outputDirectory,
                    pandocExecutableURL: pandocURL,
                    cssURL: cssURL
                )
                outcome = CompileOutcome(outputURL: result.outputURL)

            case .printPDF:
                guard let typstURL = BinaryResolver.resolve(name: "typst") else {
                    compileError = "typst isn't installed or couldn't be found (checked ~/.local/bin, "
                        + "/opt/homebrew/bin, /usr/local/bin, and PATH)."
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
