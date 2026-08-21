import Foundation

/// A `reference.docx` shipped inside the app bundle, passed to pandoc's
/// `--reference-doc` so DOCX exports pick up sane manuscript-submission styles
/// (`DOCXExportCoordinator`) instead of pandoc's generic built-in defaults.
enum BundledDOCXTemplate {
    static var referenceDocxURL: URL? {
        Bundle.module.url(forResource: "reference", withExtension: "docx", subdirectory: "DOCX")
    }
}
