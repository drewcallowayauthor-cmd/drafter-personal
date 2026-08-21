import DrafterCore
import Foundation

/// Owns one open project: its metadata and its on-disk binder tree (§7's `ProjectStore`).
/// An actor because file I/O for a given working tree should never run concurrently
/// with itself — the same discipline §7 calls for around `GitService`.
public actor Project {
    public let root: URL
    public private(set) var metadata: ProjectMetadata
    public private(set) var binderTree: BinderTree

    private let metadataStore: ProjectMetadataStore

    private init(root: URL, metadata: ProjectMetadata, binderTree: BinderTree, metadataStore: ProjectMetadataStore) {
        self.root = root
        self.metadata = metadata
        self.binderTree = binderTree
        self.metadataStore = metadataStore
    }

    public static func open(root: URL, fileWriter: AtomicFileWriting) throws -> Project {
        let metadataStore = ProjectMetadataStore(fileWriter: fileWriter)
        let metadata = try metadataStore.load(from: root)
        let binderTree = try BinderTreeBuilder.build(projectRoot: root)
        return Project(root: root, metadata: metadata, binderTree: binderTree, metadataStore: metadataStore)
    }

    /// Scaffolds a brand-new project on disk (§4.2/M0's "create project folder") and
    /// opens it. `root` must not already exist — callers pick a fresh, non-colliding
    /// path (§4.1's default is `~/Documents/Drafter/Projects/<Book Name>/`) and are
    /// expected to have already run it past `SyncedFolderGuard`.
    public static func create(root: URL, metadata: ProjectMetadata, fileWriter: AtomicFileWriting) throws -> Project {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: root.path) else {
            throw DrafterError.filesystem(underlying: "a folder already exists at \(root.path)")
        }

        for subdirectory in ["Manuscript", "FrontMatter", "BackMatter", "Notes", "Resources"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(subdirectory),
                withIntermediateDirectories: true
            )
        }

        // §4.2: Local-file mode has no `.git` to normalize for, so it skips both —
        // there's no merge tool reading `.gitattributes`, and nothing named `.gitignore`
        // to ignore anything for.
        if metadata.versionControl == .git {
            try fileWriter.write(Data(Self.gitignoreContents.utf8), to: root.appendingPathComponent(".gitignore"))
            try fileWriter.write(Data(Self.gitattributesContents.utf8), to: root.appendingPathComponent(".gitattributes"))
        }

        let metadataStore = ProjectMetadataStore(fileWriter: fileWriter)
        try metadataStore.save(metadata, to: root)

        let binderTree = try BinderTreeBuilder.build(projectRoot: root)
        return Project(root: root, metadata: metadata, binderTree: binderTree, metadataStore: metadataStore)
    }

    /// §4.2's `.gitignore` — build artifacts only; everything else is committed.
    private static let gitignoreContents = """
        .DS_Store
        Build/
        *.tmp
        """

    /// §4.2's `.gitattributes` — normalizes line endings to LF so line-ending drift
    /// between machines never produces a whole-file diff.
    private static let gitattributesContents = """
        * text=auto eol=lf
        *.md text
        *.json text
        *.jpg binary
        *.png binary
        """

    /// Rebuilds the binder tree from disk — call after an external change (FSEvents,
    /// a git integration) rather than trusting stale in-memory state.
    public func refreshBinderTree() throws {
        binderTree = try BinderTreeBuilder.build(projectRoot: root)
    }

    public func save(metadata: ProjectMetadata) throws {
        try metadataStore.save(metadata, to: root)
        self.metadata = metadata
    }

    /// §8.2's "New Chapter" — a folder under `Manuscript/` with the next available
    /// prefix, seeded with one scene so it's immediately writable rather than an empty
    /// folder the binder has nothing to show for. Returns that scene's URL so the
    /// caller can open it right away.
    @discardableResult
    public func createChapter(title: String, fileWriter: AtomicFileWriting) throws -> URL {
        let manuscriptDirectory = root.appendingPathComponent("Manuscript")
        let chapterName = FilenamePrefix.nextFilename(
            existingFilenames: existingEntryNames(in: manuscriptDirectory),
            title: title,
            extension: nil
        )
        let chapterDirectory = manuscriptDirectory.appendingPathComponent(chapterName)
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        return try createScene(title: "New Scene", in: chapterDirectory, fileWriter: fileWriter)
    }

    /// §8.2's "New Scene" — a `.md` file with the next available prefix inside
    /// `directory`, seeded with default front matter and an empty body. Works for any
    /// prefix-ordered directory (a chapter folder, or one of the flat
    /// FrontMatter/BackMatter/Notes sections), since they all follow the same §4.3
    /// ordering rule.
    @discardableResult
    public func createScene(title: String, in directory: URL, fileWriter: AtomicFileWriting) throws -> URL {
        let filename = FilenamePrefix.nextFilename(
            existingFilenames: existingEntryNames(in: directory),
            title: title,
            extension: "md"
        )
        let sceneURL = directory.appendingPathComponent(filename)
        let contents = SceneFrontMatter.serialize(SceneFrontMatter(id: UUID().uuidString), body: "")
        try fileWriter.write(Data(contents.utf8), to: sceneURL)
        try refreshBinderTree()
        return sceneURL
    }

    /// §8.2's binder rename — fixes a typo'd title without disturbing order: keeps
    /// the item's existing numeric prefix (if any) and only replaces the display
    /// name. Works for a chapter (folder or loose file) or a scene.
    @discardableResult
    public func rename(itemAt url: URL, to newTitle: String) throws -> URL {
        let filename = url.lastPathComponent
        let ext = url.pathExtension
        let stem = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        let sanitizedTitle = FilenamePrefix.sanitize(newTitle)

        let newStem: String
        if let spaceIndex = stem.firstIndex(of: " "), !stem[stem.startIndex..<spaceIndex].isEmpty,
            stem[stem.startIndex..<spaceIndex].allSatisfy(\.isNumber)
        {
            newStem = "\(stem[stem.startIndex..<spaceIndex]) \(sanitizedTitle)"
        } else {
            newStem = sanitizedTitle
        }
        let newFilename = ext.isEmpty ? newStem : "\(newStem).\(ext)"
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newFilename)

        guard newFilename != filename else { return url }
        try FileManager.default.moveItem(at: url, to: newURL)
        try refreshBinderTree()
        return newURL
    }

    /// §8.2's binder delete ("Move to Trash") — moves a scene file or an entire
    /// chapter folder (with its scenes) to the Trash rather than unlinking it, since
    /// git/snapshot history may not have caught up yet (the autocommit debounce is up
    /// to 90s, §6.4) — a permanent `removeItem` could lose work no history entry ever
    /// covered. Returns the Trash location so a caller could offer "Undo" (not yet
    /// wired up in the UI).
    @discardableResult
    public func delete(itemAt url: URL) throws -> URL {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        try refreshBinderTree()
        return (trashedURL as URL?) ?? url
    }

    /// §4.3/§8.2's drag-to-reorder — `orderedURLs` is the caller's desired new order
    /// for every item in one directory (a chapter's scenes, a flat section, or
    /// Manuscript's chapters); prefixes are resequenced densely to match. Renames go
    /// through a temporary name first so a swap (e.g. `01` ↔ `02`) never collides
    /// mid-move.
    public func reorder(orderedURLs: [URL]) throws {
        guard let directory = orderedURLs.first?.deletingLastPathComponent() else { return }
        let displayNames = orderedURLs.map { FilenamePrefix.parse($0.lastPathComponent).displayName }
        let extensions = orderedURLs.map(\.pathExtension)
        let digits = orderedURLs.count > 99 ? 3 : 2
        let newStems = FilenamePrefix.resequence(displayNames: displayNames, digits: digits)
        let newFilenames = zip(newStems, extensions).map { stem, ext in ext.isEmpty ? stem : "\(stem).\(ext)" }

        let fileManager = FileManager.default
        let temporaryURLs = try orderedURLs.map { url -> URL in
            let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString)-\(url.lastPathComponent)")
            try fileManager.moveItem(at: url, to: temporaryURL)
            return temporaryURL
        }
        for (temporaryURL, newFilename) in zip(temporaryURLs, newFilenames) {
            try fileManager.moveItem(at: temporaryURL, to: directory.appendingPathComponent(newFilename))
        }
        try refreshBinderTree()
    }

    /// §8.2's cross-chapter drag — moves a scene into `chapterDirectory` (which may
    /// be the scene's current chapter, for a same-chapter reorder), inserting it
    /// immediately before `targetURL`, or at the end when `targetURL` is `nil`.
    /// Takes a "before" URL rather than a numeric index so callers never have to
    /// account for the moving item's own position shifting the target's index.
    public func moveScene(at url: URL, toChapterDirectory chapterDirectory: URL, before targetURL: URL?) throws {
        let sourceDirectory = url.deletingLastPathComponent()

        if sourceDirectory == chapterDirectory {
            var urls = orderedEntryURLs(in: sourceDirectory)
            urls.removeAll { $0 == url }
            let index = targetURL.flatMap { target in urls.firstIndex { $0 == target } } ?? urls.count
            urls.insert(url, at: index)
            try reorder(orderedURLs: urls)
            return
        }

        // Move to a temporary name in the destination first, then resequence both
        // directories — mirrors `reorder`'s own two-phase approach, so a scene
        // landing on a prefix its destination already uses never collides. Unlike
        // `reorder`'s own UUID-named temp files (which it never re-parses), this one
        // gets re-read by `reorder` below via `FilenamePrefix.parse` when computing
        // `destinationURLs`'s display names — so it needs an absurdly-high-but-valid
        // numeric prefix rather than a UUID, or that re-parse would take the whole
        // garbled filename as the display name instead of just the title.
        let displayName = FilenamePrefix.parse(url.lastPathComponent).displayName
        let ext = url.pathExtension
        let temporaryStem = "999999999 \(displayName)"
        let temporaryFilename = ext.isEmpty ? temporaryStem : "\(temporaryStem).\(ext)"
        let temporaryURL = chapterDirectory.appendingPathComponent(temporaryFilename)
        try FileManager.default.moveItem(at: url, to: temporaryURL)

        let remainingSourceURLs = orderedEntryURLs(in: sourceDirectory)
        if !remainingSourceURLs.isEmpty {
            try reorder(orderedURLs: remainingSourceURLs)
        }

        var destinationURLs = orderedEntryURLs(in: chapterDirectory).filter { $0 != temporaryURL }
        let index = targetURL.flatMap { target in destinationURLs.firstIndex { $0 == target } } ?? destinationURLs.count
        destinationURLs.insert(temporaryURL, at: index)
        try reorder(orderedURLs: destinationURLs)
    }

    /// Drag-and-drop import of an external file (Finder) into a prefix-ordered
    /// directory — currently used for Notes' reference documents, which unlike scenes
    /// keep their original extension rather than becoming `.md`.
    @discardableResult
    public func importFile(from sourceURL: URL, into directory: URL) throws -> URL {
        let ext = sourceURL.pathExtension
        let filename = FilenamePrefix.nextFilename(
            existingFilenames: existingEntryNames(in: directory),
            title: sourceURL.deletingPathExtension().lastPathComponent,
            extension: ext.isEmpty ? nil : ext
        )
        let destinationURL = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        try refreshBinderTree()
        return destinationURL
    }

    /// Sets the book cover (§4.5's `compile.coverImage`) — copies `sourceURL` into
    /// `Resources/` as `cover.<ext>`, replacing any previous cover file, and persists
    /// the new path in `project.json`.
    @discardableResult
    public func setCoverImage(from sourceURL: URL, fileWriter: AtomicFileWriting) throws -> URL {
        let fileManager = FileManager.default
        let resourcesDirectory = root.appendingPathComponent("Resources")
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        for existing in existingEntryNames(in: resourcesDirectory)
        where (existing as NSString).deletingPathExtension == "cover" {
            try? fileManager.removeItem(at: resourcesDirectory.appendingPathComponent(existing))
        }

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let coverURL = resourcesDirectory.appendingPathComponent("cover.\(ext)")
        try fileWriter.write(try Data(contentsOf: sourceURL), to: coverURL)

        var updatedMetadata = metadata
        updatedMetadata.compile.coverImage = "Resources/cover.\(ext)"
        try save(metadata: updatedMetadata)

        return coverURL
    }

    /// §8.3 point 8's project-wide find (⇧⌘F) — searches the in-memory `binderTree`
    /// against scene bodies read fresh from disk, so it always reflects the latest
    /// saved content even though the tree structure itself is cached.
    public func search(options: ProjectSearchOptions) -> [ProjectSearchMatch] {
        ProjectSearchService.search(binderTree: binderTree, options: options)
    }

    /// Applies a batch of replacements from a prior `search(options:)`. Callers editing
    /// one of the matched scenes right now are responsible for flushing that scene's
    /// pending autosave first (so this doesn't overwrite it) and reloading it after (so
    /// the open editor doesn't go stale) — this actor only knows about the on-disk state.
    @discardableResult
    public func replace(matches: [ProjectSearchMatch], replacement: String, fileWriter: AtomicFileWriting) throws -> Set<URL> {
        try ProjectSearchService.replace(matches: matches, replacement: replacement, fileWriter: fileWriter)
    }

    private func orderedEntryURLs(in directory: URL) -> [URL] {
        FilenamePrefix.sort(existingEntryNames(in: directory)).map { directory.appendingPathComponent($0) }
    }

    private func existingEntryNames(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}
