import DrafterCore
import Foundation

/// §9.3's `epub.css`: shipped as an editable file in Application Support, not
/// regenerated once it exists, so hand-tuning survives — matching the same "editable,
/// generated once" contract as front/back matter (§9.2).
enum EPUBStylesheetManager {
    static let defaultCSS = """
        body {
          font-family: Georgia, "Times New Roman", serif;
          text-align: justify;
          hyphens: auto;
          -webkit-hyphens: auto;
          -epub-hyphens: auto;
          line-height: 1.4;
        }

        p {
          margin: 0;
          text-indent: 1.2em;
        }

        h1 + p, h2 + p, hr + p {
          text-indent: 0;
        }

        h1, h2 {
          page-break-before: always;
          margin-top: 3em;
          margin-bottom: 1.5em;
          font-weight: normal;
          text-align: center;
        }

        hr {
          border: none;
          text-align: center;
          margin: 2em 0;
        }

        hr::before {
          content: "•  •  •";
          letter-spacing: 0.3em;
        }
        """

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Drafter", isDirectory: true)
    }

    /// Writes the default stylesheet only if one doesn't already exist, and returns its
    /// location either way.
    @discardableResult
    static func ensureStylesheetExists(
        fileWriter: AtomicFileWriting,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = try applicationSupportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cssURL = directory.appendingPathComponent("epub.css")
        if !fileManager.fileExists(atPath: cssURL.path) {
            try fileWriter.write(Data(defaultCSS.utf8), to: cssURL)
        }
        return cssURL
    }
}
