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
            Form {
                Section("Target") {
                    Picker("Target", selection: $target) {
                        ForEach(CompileTarget.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Output Location") {
                    HStack {
                        Text(outputDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { isOutputPickerPresented = true }
                    }
                }

                Section("Front & Back Matter") {
                    Toggle("Include Front Matter", isOn: $includeFrontMatter)
                    Toggle("Include Back Matter", isOn: $includeBackMatter)
                }

                Section("Chapters") {
                    TextField("Chapter Title Format", text: $chapterTitleFormat)
                    Text("Preview: \(firstHeadingPreview)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Scene Separator", text: $sceneSeparator)
                }

                if target == .printPDF {
                    Section("Print") {
                        Picker("Trim Size", selection: $trimSize) {
                            ForEach(TrimSize.allCases, id: \.self) { size in
                                Text("\(size.widthInches, specifier: "%g")\" × \(size.heightInches, specifier: "%g")\"")
                                    .tag(size)
                            }
                        }
                        TextField("Body Font", text: $bodyFont)
                        HStack {
                            Text("Point Size")
                            Spacer()
                            TextField("", value: $bodyPointSize, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Estimate") {
                    Text("\(wordCountEstimate) words")
                }
            }
            .formStyle(.grouped)

            // Deliberately outside the scrollable Form: a success/failure/in-progress
            // result added as just another trailing Section was easy to miss without
            // scrolling, especially since a small manuscript compiles almost instantly
            // and gave no visible cue that anything had happened at all.
            statusBanner

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Compile") { Task { await compile() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCompiling)
            }
            .padding()
        }
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
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if isCompiling {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Compiling…")
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        } else if let compileError {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Compile Failed").bold()
                }
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(compileError)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
            .padding()
            .background(Color.red.opacity(0.1))
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
                let cssURL = try? EPUBStylesheetManager.ensureStylesheetExists(fileWriter: LiveAtomicFileWriter())
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
                    trimSize: trimSize
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
            compileError = String(describing: error)
        }
    }
}
