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

    /// Rebuilds the binder tree from disk — call after an external change (FSEvents,
    /// a git integration) rather than trusting stale in-memory state.
    public func refreshBinderTree() throws {
        binderTree = try BinderTreeBuilder.build(projectRoot: root)
    }

    public func save(metadata: ProjectMetadata) throws {
        try metadataStore.save(metadata, to: root)
        self.metadata = metadata
    }
}
