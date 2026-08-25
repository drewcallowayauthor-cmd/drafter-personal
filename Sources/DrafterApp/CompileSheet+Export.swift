import AppKit
import CompileService
import DrafterCore
import ProjectStore
import SwiftUI

/// The compile orchestration and per-target export logic for `CompileSheet`, split
/// out to keep the main file's function-body and type-body lengths under
/// SwiftLint's limits.
extension CompileSheet {
    func compile() async {
        isCompiling = true
        compileError = nil
        defer { isCompiling = false }

        let pandocOverride = AppPreferences.shared.pandocPathOverride.map { URL(fileURLWithPath: $0) }
        guard let pandocURL = BinaryResolver.resolve(
            name: "pandoc", override: pandocOverride, bundled: BundledBinaries.pandocURL
        ) else {
            compileError = "pandoc isn't installed or couldn't be found (checked the app's own bundled copy — "
                + "arm64 Macs only — plus ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, and PATH)."
            return
        }

        let exportMetadata = buildExportMetadata()

        do {
            let outcome: CompileOutcome?
            switch target {
            case .epub:
                outcome = try await exportEPUB(pandocURL: pandocURL, exportMetadata: exportMetadata)
            case .printPDF:
                outcome = try await exportPrintPDF(pandocURL: pandocURL, exportMetadata: exportMetadata)
            case .docx:
                outcome = try await exportDOCX(pandocURL: pandocURL, exportMetadata: exportMetadata)
            }
            guard let outcome else { return }

            onCompiled(outcome)
            onCancel()
        } catch {
            compileError = error.localizedDescription
        }
    }

    private func buildExportMetadata() -> ProjectMetadata {
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
        return exportMetadata
    }

    private func exportEPUB(pandocURL: URL, exportMetadata: ProjectMetadata) async throws -> CompileOutcome {
        let cssURL = try EPUBStylesheetManager.ensureStylesheetExists(
            template: epubTemplate,
            fileWriter: LiveAtomicFileWriter()
        )
        let coordinator = EPUBExportCoordinator(
            processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter()
        )
        let result = try await coordinator.export(
            metadata: exportMetadata,
            binderTree: binderTree,
            workingTree: workingTree,
            outputDirectory: outputDirectory,
            pandocExecutableURL: pandocURL,
            cssURL: cssURL,
            epubTemplate: epubTemplate
        )
        return CompileOutcome(outputURL: result.outputURL)
    }

    private func exportPrintPDF(pandocURL: URL, exportMetadata: ProjectMetadata) async throws -> CompileOutcome? {
        let typstOverride = AppPreferences.shared.typstPathOverride.map { URL(fileURLWithPath: $0) }
        guard let typstURL = BinaryResolver.resolve(
            name: "typst", override: typstOverride, bundled: BundledBinaries.typstURL
        ) else {
            compileError = "typst isn't installed or couldn't be found (checked the app's own bundled copy — "
                + "arm64 Macs only — plus ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, and PATH)."
            return nil
        }
        let coordinator = PrintExportCoordinator(
            processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter()
        )
        let result = try await coordinator.export(PrintExportCoordinator.ExportRequest(
            metadata: exportMetadata,
            binderTree: binderTree,
            workingTree: workingTree,
            outputDirectory: outputDirectory,
            pandocExecutableURL: pandocURL,
            typstExecutableURL: typstURL,
            trimSize: trimSize,
            fontDirectoryURLs: BundledFonts.fontsDirectoryURL.map { [$0] } ?? []
        ))
        return CompileOutcome(outputURL: result.outputURL)
    }

    private func exportDOCX(pandocURL: URL, exportMetadata: ProjectMetadata) async throws -> CompileOutcome {
        let coordinator = DOCXExportCoordinator(
            processRunner: LiveProcessRunner(), fileWriter: LiveAtomicFileWriter()
        )
        let result = try await coordinator.export(
            metadata: exportMetadata,
            binderTree: binderTree,
            workingTree: workingTree,
            outputDirectory: outputDirectory,
            pandocExecutableURL: pandocURL
        )
        return CompileOutcome(outputURL: result.outputURL)
    }
}
