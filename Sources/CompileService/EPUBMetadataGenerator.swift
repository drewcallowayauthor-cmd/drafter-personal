import Foundation
import ProjectStore

/// Generates `meta.yaml` for pandoc's `--metadata-file` (§9.3): title, subtitle,
/// creator, publisher, date, language, description, rights, identifier (ISBN if
/// present, else a stable identifier from `project.id`). Hand-rolled YAML rather than
/// a dependency — the fields are all flat scalars, so a small string escaper covers it.
public enum EPUBMetadataGenerator {
    public static func metaYAML(for metadata: ProjectMetadata, generatedDate: Date = Date()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: generatedDate)

        let identifier = metadata.isbn.isEmpty ? metadata.id : metadata.isbn
        let rights = "Copyright © \(metadata.copyrightYear) by \(metadata.author)"

        var lines: [String] = []
        lines.append("title: \(yamlString(metadata.title))")
        if !metadata.subtitle.isEmpty {
            lines.append("subtitle: \(yamlString(metadata.subtitle))")
        }
        lines.append("creator: \(yamlString(metadata.author))")
        if !metadata.publisher.isEmpty {
            lines.append("publisher: \(yamlString(metadata.publisher))")
        }
        lines.append("date: \(yamlString(dateString))")
        lines.append("language: \(yamlString(metadata.language))")
        if !metadata.description.isEmpty {
            lines.append("description: \(yamlString(metadata.description))")
        }
        lines.append("rights: \(yamlString(rights))")
        lines.append("identifier: \(yamlString(identifier))")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
