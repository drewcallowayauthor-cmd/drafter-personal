import Foundation

/// Generates the "Contents" front-matter page — spliced into the assembled markdown
/// right after Copyright by `EPUBExportCoordinator`. Unlike the other front/back
/// matter files (`FrontBackMatterTemplate`), Contents isn't a static, once-generated,
/// user-editable file: its content is the real chapter list, which isn't known until
/// compile time.
public enum EPUBTableOfContentsGenerator {
    public struct Entry: Equatable, Sendable {
        public let title: String
        public let anchorID: String

        public init(title: String, anchorID: String) {
            self.title = title
            self.anchorID = anchorID
        }
    }

    /// Plain hyperlinks, no bullets or numbers (`.toc`'s CSS, § EPUBStylesheetManager)
    /// — wrapped in a fenced div so that class has something to target, since a bare
    /// bullet list has no attachment point of its own in Pandoc's markdown.
    public static func markdown(entries: [Entry]) -> String {
        guard !entries.isEmpty else { return "" }
        let items = entries.map { "- [\($0.title)](#\($0.anchorID))" }.joined(separator: "\n")
        return """
            # Contents

            ::: {.toc}
            \(items)
            :::
            """
    }
}
