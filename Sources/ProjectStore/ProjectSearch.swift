import DrafterCore
import Foundation

/// §8.3 point 8's project-wide find & replace (⇧⌘F): the query and its matching rules.
public struct ProjectSearchOptions: Sendable, Equatable {
    public var query: String
    public var caseSensitive: Bool
    public var matchWholeWord: Bool

    public init(query: String, caseSensitive: Bool = false, matchWholeWord: Bool = false) {
        self.query = query
        self.caseSensitive = caseSensitive
        self.matchWholeWord = matchWholeWord
    }
}

/// One occurrence of the query in one scene's body. `range` is in terms of the scene's
/// body text (front matter stripped, matching what `SceneTextView` displays) so a caller
/// can hand it straight to `NSTextView.setSelectedRange(_:)` after opening the scene.
public struct ProjectSearchMatch: Sendable, Equatable, Identifiable {
    public let id: String
    public let sceneURL: URL
    public let sceneDisplayName: String
    public let range: NSRange
    /// A short window of body text around the match, for the results list.
    public let snippet: String
    /// Where `range` falls within `snippet`, for highlighting the matched substring.
    public let snippetMatchRange: NSRange

    public init(sceneURL: URL, sceneDisplayName: String, range: NSRange, snippet: String, snippetMatchRange: NSRange) {
        self.id = "\(sceneURL.path)#\(range.location),\(range.length)"
        self.sceneURL = sceneURL
        self.sceneDisplayName = sceneDisplayName
        self.range = range
        self.snippet = snippet
        self.snippetMatchRange = snippetMatchRange
    }
}

/// Walks every scene in a `BinderTree` (Manuscript, Front Matter, Back Matter, and
/// Notes' `.md` files — Notes' non-markdown reference documents aren't text to search)
/// looking for `ProjectSearchOptions.query`, and can apply a batch of replacements back
/// to disk. Pure filesystem reads/writes, no in-memory project state, so it never needs
/// to know whether a matched scene is currently open in the editor — callers that care
/// (§7's autosave) are responsible for flushing dirty edits first and reloading after.
public enum ProjectSearchService {
    public static func search(binderTree: BinderTree, options: ProjectSearchOptions) -> [ProjectSearchMatch] {
        guard !options.query.isEmpty, let regex = regex(for: options) else { return [] }

        var results: [ProjectSearchMatch] = []
        for scene in scenes(in: binderTree) {
            let document: SceneDocument
            do {
                document = try SceneDocument.load(from: scene.url)
            } catch {
                DrafterLog.projectStore.error("Skipping \(scene.url.path, privacy: .public) in search — failed to load: \(error, privacy: .public)")
                continue
            }
            results.append(contentsOf: matches(in: document.body, regex: regex, sceneURL: scene.url, displayName: scene.displayName))
        }
        return results
    }

    /// Applies `replacement` at every given match, grouped by file so each is rewritten
    /// once regardless of how many matches it contains. Ranges within a file are applied
    /// back-to-front so an earlier replacement's length change never invalidates a later
    /// one's offset. Returns the set of scene URLs actually rewritten.
    @discardableResult
    public static func replace(
        matches: [ProjectSearchMatch],
        replacement: String,
        fileWriter: AtomicFileWriting
    ) throws -> Set<URL> {
        var rewrittenURLs: Set<URL> = []
        for (sceneURL, matchesInScene) in Dictionary(grouping: matches, by: \.sceneURL) {
            var document: SceneDocument
            do {
                document = try SceneDocument.load(from: sceneURL)
            } catch {
                DrafterLog.projectStore.error("Skipping \(sceneURL.path, privacy: .public) in replace — failed to load: \(error, privacy: .public)")
                continue
            }
            let mutableBody = NSMutableString(string: document.body)
            for match in matchesInScene.sorted(by: { $0.range.location > $1.range.location }) {
                guard match.range.location + match.range.length <= mutableBody.length else { continue }
                mutableBody.replaceCharacters(in: match.range, with: replacement)
            }
            document.body = mutableBody as String
            try fileWriter.write(Data(document.serializedContents().utf8), to: sceneURL)
            rewrittenURLs.insert(sceneURL)
        }
        return rewrittenURLs
    }

    private static func scenes(in tree: BinderTree) -> [SceneNode] {
        var scenes: [SceneNode] = []
        for chapter in tree.manuscript {
            if chapter.isLooseFile {
                scenes.append(SceneNode(url: chapter.url, displayName: chapter.displayName))
            } else {
                scenes.append(contentsOf: chapter.scenes)
            }
        }
        scenes.append(contentsOf: tree.frontMatter)
        scenes.append(contentsOf: tree.backMatter)
        scenes.append(contentsOf: tree.notes.filter { $0.url.pathExtension == "md" })
        return scenes
    }

    private static func regex(for options: ProjectSearchOptions) -> NSRegularExpression? {
        var pattern = NSRegularExpression.escapedPattern(for: options.query)
        if options.matchWholeWord {
            pattern = "\\b\(pattern)\\b"
        }
        return try? NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
    }

    private static func matches(
        in body: String,
        regex: NSRegularExpression,
        sceneURL: URL,
        displayName: String
    ) -> [ProjectSearchMatch] {
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        return regex.matches(in: body, range: fullRange).map { result in
            let (snippet, snippetMatchRange) = snippet(in: nsBody, around: result.range)
            return ProjectSearchMatch(
                sceneURL: sceneURL,
                sceneDisplayName: displayName,
                range: result.range,
                snippet: snippet,
                snippetMatchRange: snippetMatchRange
            )
        }
    }

    /// A window of plain-text context around a match, entirely in `NSString`/UTF-16
    /// terms so `snippetMatchRange` lines up with what `Text`'s `AttributedString`
    /// highlighting (also UTF-16-indexed) expects.
    private static func snippet(in nsBody: NSString, around range: NSRange, contextLength: Int = 40) -> (String, NSRange) {
        let start = max(range.location - contextLength, 0)
        let end = min(range.location + range.length + contextLength, nsBody.length)
        let snippetText = nsBody.substring(with: NSRange(location: start, length: end - start))
        let matchRangeInSnippet = NSRange(location: range.location - start, length: range.length)
        return (snippetText, matchRangeInSnippet)
    }
}
