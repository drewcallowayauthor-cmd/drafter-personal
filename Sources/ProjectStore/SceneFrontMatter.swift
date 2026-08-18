import Foundation

/// §4.4's status progression.
public enum SceneStatus: String, Sendable, Equatable, CaseIterable {
    case outline
    case draft
    case revised
    case final
}

/// Per-scene metadata living in a scene file's YAML front matter (§4.4). Deliberately not
/// a general YAML parser — the front-matter block is always this fixed, flat shape, so a
/// hand-rolled `key: value` reader avoids pulling in a YAML dependency for four fields.
public struct SceneFrontMatter: Sendable, Equatable {
    public var synopsis: String
    public var status: SceneStatus
    public var compile: Bool
    public var notes: String

    public init(synopsis: String = "", status: SceneStatus = .draft, compile: Bool = true, notes: String = "") {
        self.synopsis = synopsis
        self.status = status
        self.compile = compile
        self.notes = notes
    }

    /// Splits a scene file's raw contents into its front matter and prose body. A file
    /// with no `---` block, or a malformed one, is treated as having no front matter —
    /// its entire contents become the body, defaults fill in the metadata.
    public static func parse(_ contents: String) -> (frontMatter: SceneFrontMatter, body: String) {
        let lines = contents.components(separatedBy: "\n")
        guard lines.first == "---",
            let closingIndex = lines.dropFirst().firstIndex(where: { $0 == "---" })
        else {
            return (SceneFrontMatter(), contents)
        }

        var frontMatter = SceneFrontMatter()
        for line in lines[1..<closingIndex] {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "synopsis": frontMatter.synopsis = value
            case "status": frontMatter.status = SceneStatus(rawValue: value) ?? .draft
            case "compile": frontMatter.compile = (value == "true")
            case "notes": frontMatter.notes = value
            default: break
            }
        }

        let bodyLines = lines[(closingIndex + 1)...].drop { $0.isEmpty }
        return (frontMatter, bodyLines.joined(separator: "\n"))
    }

    /// Reassembles a scene file's raw contents from front matter and body. The compiler
    /// strips this block before concatenation (§4.4); it never reaches export output.
    public static func serialize(_ frontMatter: SceneFrontMatter, body: String) -> String {
        """
        ---
        synopsis: \(frontMatter.synopsis)
        status: \(frontMatter.status.rawValue)
        compile: \(frontMatter.compile)
        notes: \(frontMatter.notes)
        ---

        \(body)
        """
    }
}
