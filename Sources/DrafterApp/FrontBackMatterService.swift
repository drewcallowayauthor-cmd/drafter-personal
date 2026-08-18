import DrafterCore
import Foundation
import ProjectStore

/// Thin I/O glue around `FrontBackMatterTemplate` (§9.2) — the template content
/// generation itself is pure and lives in ProjectStore; this just decides file paths
/// and talks to the filesystem.
enum FrontBackMatterService {
    /// Writes any of the six standard files that don't already exist. Existing files
    /// are left untouched, even if empty — this is additive scaffolding, not a sync.
    @discardableResult
    static func generateMissing(
        metadata: ProjectMetadata,
        workingTree: URL,
        fileWriter: AtomicFileWriting,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var created: [URL] = []
        for template in FrontBackMatterTemplate.allCases {
            let fileURL = url(for: template, workingTree: workingTree)
            guard !fileManager.fileExists(atPath: fileURL.path) else { continue }
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileWriter.write(Data(template.content(for: metadata).utf8), to: fileURL)
            created.append(fileURL)
        }
        return created
    }

    /// "Regenerate from Template" (§9.2) — overwrites one file with fresh content.
    /// Callers are responsible for confirming with the user first; this doesn't ask.
    static func regenerate(
        template: FrontBackMatterTemplate,
        metadata: ProjectMetadata,
        workingTree: URL,
        fileWriter: AtomicFileWriting
    ) throws {
        try fileWriter.write(
            Data(template.content(for: metadata).utf8),
            to: url(for: template, workingTree: workingTree)
        )
    }

    private static func url(for template: FrontBackMatterTemplate, workingTree: URL) -> URL {
        let directory = template.section == .front ? "FrontMatter" : "BackMatter"
        return workingTree.appendingPathComponent(directory).appendingPathComponent(template.filename)
    }
}
