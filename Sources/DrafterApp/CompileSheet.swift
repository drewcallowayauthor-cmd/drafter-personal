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

    @State var target: CompileTarget = .epub
    @State var epubTemplate: ManuscriptTemplate = .novel
    @State var outputDirectory: URL
    @State var chapterTitleFormat: String
    @State var sceneSeparator: String
    @State var includeFrontMatter: Bool
    @State var includeBackMatter: Bool
    @State var trimSize: TrimSize
    @State var bodyFont: String
    @State var bodyPointSize: Double
    @State var firstLineIndentEm: Double
    @State var headingFont: String
    @State var manuscriptFont: String
    @State private var isOutputPickerPresented = false
    @State var isCompiling = false
    @State var compileError: String?
    @State var wordCountEstimate = 0

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
                try? WordCountAggregator.aggregate(binderTree: binderTree) {
                    try String(contentsOf: $0, encoding: .utf8)
                }
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
        NocturneDropdown(
            label: "Manuscript Font", selection: $manuscriptFont, options: ["Times New Roman", "Courier New"]
        ) { $0 }
    }
}
