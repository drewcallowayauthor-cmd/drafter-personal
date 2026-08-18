import DrafterCore
import Foundation

/// Reads and writes `project.json` (§4.5). Writes go through `AtomicFileWriting` so a
/// crash or disk-full mid-save can never leave a truncated file (§6.5).
public struct ProjectMetadataStore: Sendable {
    private let fileWriter: AtomicFileWriting
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileWriter: AtomicFileWriting) {
        self.fileWriter = fileWriter
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(from projectRoot: URL) throws -> ProjectMetadata {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("project.json"))
        return try decoder.decode(ProjectMetadata.self, from: data)
    }

    public func save(_ metadata: ProjectMetadata, to projectRoot: URL) throws {
        let data = try encoder.encode(metadata)
        try fileWriter.write(data, to: projectRoot.appendingPathComponent("project.json"))
    }
}
