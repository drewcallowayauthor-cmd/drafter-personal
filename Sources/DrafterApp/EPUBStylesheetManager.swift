import DrafterCore
import Foundation

/// §9.3's `epub.css`: shipped as an editable file in Application Support, not
/// regenerated once it exists, so hand-tuning survives — matching the same "editable,
/// generated once" contract as front/back matter (§9.2).
enum EPUBStylesheetManager {
    /// `.novel` keeps the original `epub.css` filename so existing hand-edited files
    /// keep working untouched; `.shortStory` gets its own file so each template's
    /// "write once, then user-editable" contract stays independent of the other.
    private static func filename(for template: ManuscriptTemplate) -> String {
        switch template {
        case .novel: return "epub.css"
        case .shortStory: return "epub-short-story.css"
        }
    }

    private static func content(for template: ManuscriptTemplate) -> String {
        switch template {
        case .novel: return defaultCSS
        case .shortStory: return shortStoryCSS
        }
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Drafter", isDirectory: true)
    }

    /// Writes the template's default stylesheet only if one doesn't already exist, and
    /// returns its location either way — each template has its own file, so switching
    /// templates never touches (or loses) the other's hand-edited stylesheet.
    ///
    /// `directoryOverride` exists only for tests — it lets them target a temp directory
    /// instead of the real `~/Library/Application Support/Drafter`, which would
    /// otherwise risk clobbering a real user's hand-edited stylesheet.
    @discardableResult
    static func ensureStylesheetExists(
        template: ManuscriptTemplate,
        fileWriter: AtomicFileWriting,
        fileManager: FileManager = .default,
        directoryOverride: URL? = nil
    ) throws -> URL {
        let directory = try directoryOverride ?? applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cssURL = directory.appendingPathComponent(filename(for: template))
        if !fileManager.fileExists(atPath: cssURL.path) {
            try fileWriter.write(Data(content(for: template).utf8), to: cssURL)
        }
        return cssURL
    }
}
