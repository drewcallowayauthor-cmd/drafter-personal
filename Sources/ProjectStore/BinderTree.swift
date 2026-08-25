import DrafterCore
import Foundation

/// A single scene file — a leaf in the binder (§4.2).
public struct SceneNode: Sendable, Equatable, Identifiable {
    public let url: URL
    public let displayName: String

    public var id: URL { url }

    public init(url: URL, displayName: String) {
        self.url = url
        self.displayName = displayName
    }
}

/// A chapter: either a `Manuscript/` subfolder containing ordered scenes, or a loose
/// `.md` file directly under `Manuscript/`, which is its own single-scene chapter (§4.2).
public struct ChapterNode: Sendable, Equatable, Identifiable {
    public let url: URL
    public let displayName: String
    public let scenes: [SceneNode]
    public let isLooseFile: Bool

    public var id: URL { url }

    public init(url: URL, displayName: String, scenes: [SceneNode], isLooseFile: Bool) {
        self.url = url
        self.displayName = displayName
        self.scenes = scenes
        self.isLooseFile = isLooseFile
    }
}

/// The on-disk project tree (§4.2): `Manuscript/` holds chapters, the other three
/// sections are flat, prefix-ordered lists of `.md` files.
public struct BinderTree: Sendable, Equatable {
    public let manuscript: [ChapterNode]
    public let frontMatter: [SceneNode]
    public let backMatter: [SceneNode]
    public let notes: [SceneNode]

    public init(manuscript: [ChapterNode], frontMatter: [SceneNode], backMatter: [SceneNode], notes: [SceneNode]) {
        self.manuscript = manuscript
        self.frontMatter = frontMatter
        self.backMatter = backMatter
        self.notes = notes
    }
}

/// Builds a `BinderTree` by walking a project's working tree on disk. Pure filesystem
/// reads — no mutation — so it's exercised with real temp directories in tests rather
/// than a filesystem fake.
public enum BinderTreeBuilder {
    public static func build(projectRoot: URL, fileManager: FileManager = .default) throws -> BinderTree {
        BinderTree(
            manuscript: try buildManuscript(
                at: projectRoot.appendingPathComponent("Manuscript"),
                fileManager: fileManager
            ),
            frontMatter: try buildFlatSection(
                at: projectRoot.appendingPathComponent("FrontMatter"),
                fileManager: fileManager
            ),
            backMatter: try buildFlatSection(
                at: projectRoot.appendingPathComponent("BackMatter"),
                fileManager: fileManager
            ),
            // Unlike Front/Back Matter (generated `.md` only), Notes also holds
            // reference documents dropped in from Finder (PDFs, images, etc.) — so it
            // takes every regular file, not just markdown.
            notes: try buildFlatSection(
                at: projectRoot.appendingPathComponent("Notes"),
                fileManager: fileManager,
                extensions: nil
            )
        )
    }

    private static func buildManuscript(at directory: URL, fileManager: FileManager) throws -> [ChapterNode] {
        guard let entries = try contentsIfPresent(of: directory, fileManager: fileManager) else { return [] }

        let chapterFolders = entries.filter { isDirectory($0, fileManager: fileManager) }
        let looseFiles = entries.filter { $0.pathExtension == "md" }

        let orderedNames = FilenamePrefix.sort(entries.map(\.lastPathComponent))
        let byFilename = Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })

        return try orderedNames.compactMap { filename -> ChapterNode? in
            guard let url = byFilename[filename] else { return nil }
            let displayName = FilenamePrefix.parse(filename).displayName

            if chapterFolders.contains(url) {
                let scenes = try buildScenes(in: url, fileManager: fileManager)
                return ChapterNode(url: url, displayName: displayName, scenes: scenes, isLooseFile: false)
            } else if looseFiles.contains(url) {
                return ChapterNode(url: url, displayName: displayName, scenes: [], isLooseFile: true)
            }
            return nil
        }
    }

    private static func buildScenes(in chapterDirectory: URL, fileManager: FileManager) throws -> [SceneNode] {
        let entries = try contents(of: chapterDirectory, fileManager: fileManager)
            .filter { $0.pathExtension == "md" }
        return orderedSceneNodes(from: entries)
    }

    /// `extensions: nil` accepts every regular file (still skipping subdirectories);
    /// otherwise only files whose extension is in the set.
    private static func buildFlatSection(
        at directory: URL,
        fileManager: FileManager,
        extensions: Set<String>? = ["md"]
    ) throws -> [SceneNode] {
        guard let entries = try contentsIfPresent(of: directory, fileManager: fileManager) else { return [] }
        let files = entries.filter { !isDirectory($0, fileManager: fileManager) }
        let matching = extensions.map { allowed in files.filter { allowed.contains($0.pathExtension) } } ?? files
        return orderedSceneNodes(from: matching)
    }

    private static func orderedSceneNodes(from entries: [URL]) -> [SceneNode] {
        let orderedNames = FilenamePrefix.sort(entries.map(\.lastPathComponent))
        let byFilename = Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })
        return orderedNames.compactMap { filename in
            guard let url = byFilename[filename] else { return nil }
            return SceneNode(url: url, displayName: FilenamePrefix.parse(filename).displayName)
        }
    }

    private static func contents(of directory: URL, fileManager: FileManager) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    /// `nil` when `directory` legitimately doesn't exist yet (a brand-new project, or
    /// an optional section like Notes/ that's never been used) — that's not an error.
    /// Any other listing failure (permissions, an unmounted volume) propagates instead
    /// of silently presenting as "this section is empty."
    private static func contentsIfPresent(of directory: URL, fileManager: FileManager) throws -> [URL]? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        do {
            return try contents(of: directory, fileManager: fileManager)
        } catch {
            // swiftlint:disable:next line_length
            DrafterLog.projectStore.error("Failed to list \(directory.path, privacy: .public): \(error, privacy: .public)")
            throw error
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
