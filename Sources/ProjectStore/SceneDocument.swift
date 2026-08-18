import Foundation

/// Text plus parsed front matter for one open scene, with dirty tracking (§7). A value
/// type: dirtiness is computed by comparing against the last-saved snapshot rather than
/// tracked with a mutable flag, so there's no way for it to drift out of sync with the
/// actual content.
public struct SceneDocument: Sendable, Equatable {
    public let url: URL
    public var frontMatter: SceneFrontMatter
    public var body: String

    private let savedFrontMatter: SceneFrontMatter
    private let savedBody: String

    public var isDirty: Bool {
        frontMatter != savedFrontMatter || body != savedBody
    }

    public init(url: URL, frontMatter: SceneFrontMatter, body: String) {
        self.url = url
        self.frontMatter = frontMatter
        self.body = body
        self.savedFrontMatter = frontMatter
        self.savedBody = body
    }

    private init(url: URL, frontMatter: SceneFrontMatter, body: String, savedFrontMatter: SceneFrontMatter, savedBody: String) {
        self.url = url
        self.frontMatter = frontMatter
        self.body = body
        self.savedFrontMatter = savedFrontMatter
        self.savedBody = savedBody
    }

    public static func load(from url: URL) throws -> SceneDocument {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (frontMatter, body) = SceneFrontMatter.parse(raw)
        return SceneDocument(url: url, frontMatter: frontMatter, body: body)
    }

    public func serializedContents() -> String {
        SceneFrontMatter.serialize(frontMatter, body: body)
    }

    /// Returns a copy whose saved snapshot matches its current content — call after a
    /// successful write so `isDirty` goes back to `false`.
    public func markedSaved() -> SceneDocument {
        SceneDocument(
            url: url,
            frontMatter: frontMatter,
            body: body,
            savedFrontMatter: frontMatter,
            savedBody: body
        )
    }
}
