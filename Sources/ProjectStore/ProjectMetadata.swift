import Foundation

/// `ProjectMetadata.Print`'s coding keys, kept at file scope rather than nested inside
/// `Print` (itself nested inside `ProjectMetadata`) — SwiftLint's nesting rule caps
/// types at one level deep, and `Print` is already at that limit.
private enum PrintCodingKeys: String, CodingKey {
    case trimSize, bodyFont, bodyPointSize, leading, chapterOpensOn, firstLineIndentEm, headingFont
}

/// §5's onboarding choice, fixed at project creation (§4.5). `git` wires up
/// `GitService`/`RepositoryCoordinator`; `localFile` wires up `SnapshotService` instead.
public enum VersionControlMode: String, Codable, Sendable, Equatable {
    case git
    case localFile
}

/// Book-level settings, §4.5. Mirrors `project.json`'s shape, with a hand-written
/// `init(from:)` so `versionControl` can default to `.git` when decoding a project.json
/// written before this field existed, rather than failing to open every pre-existing
/// project.
public struct ProjectMetadata: Codable, Sendable, Equatable {
    public struct Series: Codable, Sendable, Equatable {
        public var name: String
        public var number: Int?

        public init(name: String = "", number: Int? = nil) {
            self.name = name
            self.number = number
        }
    }

    public struct Target: Codable, Sendable, Equatable {
        public var words: Int

        public init(words: Int = 0) {
            self.words = words
        }
    }

    public struct Compile: Codable, Sendable, Equatable {
        public var chapterTitleFormat: String
        public var sceneSeparator: String
        public var includeFrontMatter: Bool
        public var includeBackMatter: Bool
        public var coverImage: String

        public init(
            chapterTitleFormat: String = "Chapter {n}",
            sceneSeparator: String = "#",
            includeFrontMatter: Bool = true,
            includeBackMatter: Bool = true,
            coverImage: String = "Resources/cover.jpg"
        ) {
            self.chapterTitleFormat = chapterTitleFormat
            self.sceneSeparator = sceneSeparator
            self.includeFrontMatter = includeFrontMatter
            self.includeBackMatter = includeBackMatter
            self.coverImage = coverImage
        }
    }

    public struct Print: Codable, Sendable, Equatable {
        public var trimSize: String
        public var bodyFont: String
        public var bodyPointSize: Double
        public var leading: Double
        public var chapterOpensOn: String
        public var firstLineIndentEm: Double
        public var headingFont: String

        /// Defaults measured off a real compiled print PDF (Scrivener export of a
        /// finished novel) rather than assumed: Palatino at 11.5pt with ~1.46em leading
        /// (16.8pt line pitch), a ~1em first-line indent, and chapters starting on the
        /// next page regardless of recto/verso — that reference never forces a blank
        /// page to keep chapters odd. `headingFont` defaults to Times New Roman, that
        /// same reference's own choice for its chapter numerals — a deliberate
        /// contrast against the Palatino body, not a fallback.
        public init(
            trimSize: String = "5x8",
            bodyFont: String = "Palatino",
            bodyPointSize: Double = 11.5,
            leading: Double = 1.46,
            chapterOpensOn: String = "either",
            firstLineIndentEm: Double = 1.0,
            headingFont: String = "Times New Roman"
        ) {
            self.trimSize = trimSize
            self.bodyFont = bodyFont
            self.bodyPointSize = bodyPointSize
            self.leading = leading
            self.chapterOpensOn = chapterOpensOn
            self.firstLineIndentEm = firstLineIndentEm
            self.headingFont = headingFont
        }

        /// Hand-written so `firstLineIndentEm`/`headingFont` — added after the
        /// original schema — default rather than failing to decode a `project.json`
        /// written before they existed, mirroring `ProjectMetadata.init(from:)`'s own
        /// `versionControl` precedent.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: PrintCodingKeys.self)
            trimSize = try container.decode(String.self, forKey: .trimSize)
            bodyFont = try container.decode(String.self, forKey: .bodyFont)
            bodyPointSize = try container.decode(Double.self, forKey: .bodyPointSize)
            leading = try container.decode(Double.self, forKey: .leading)
            chapterOpensOn = try container.decode(String.self, forKey: .chapterOpensOn)
            firstLineIndentEm = try container.decodeIfPresent(Double.self, forKey: .firstLineIndentEm) ?? 1.0
            headingFont = try container.decodeIfPresent(String.self, forKey: .headingFont) ?? "Times New Roman"
        }
    }

    public struct Manuscript: Codable, Sendable, Equatable {
        public var address: String
        public var phone: String
        public var email: String
        public var agentName: String
        public var agentAddress: String
        public var bodyFont: String

        public init(
            address: String = "",
            phone: String = "",
            email: String = "",
            agentName: String = "",
            agentAddress: String = "",
            bodyFont: String = "Times New Roman"
        ) {
            self.address = address
            self.phone = phone
            self.email = email
            self.agentName = agentName
            self.agentAddress = agentAddress
            self.bodyFont = bodyFont
        }
    }

    public var schemaVersion: Int
    public var id: String
    public var title: String
    public var subtitle: String
    public var author: String
    public var versionControl: VersionControlMode
    public var series: Series
    public var copyrightYear: Int
    public var publisher: String
    public var isbn: String
    public var language: String
    public var description: String
    public var target: Target
    public var compile: Compile
    public var print: Print
    public var manuscript: Manuscript

    public init(
        schemaVersion: Int = 2,
        id: String = UUID().uuidString,
        title: String,
        subtitle: String = "",
        author: String,
        versionControl: VersionControlMode = .git,
        series: Series = Series(),
        copyrightYear: Int,
        publisher: String = "",
        isbn: String = "",
        language: String = "en-US",
        description: String = "",
        target: Target = Target(),
        compile: Compile = Compile(),
        print: Print = Print(),
        manuscript: Manuscript = Manuscript()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.versionControl = versionControl
        self.series = series
        self.copyrightYear = copyrightYear
        self.publisher = publisher
        self.isbn = isbn
        self.language = language
        self.description = description
        self.target = target
        self.compile = compile
        self.print = print
        self.manuscript = manuscript
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, subtitle, author, versionControl, series, copyrightYear,
            publisher, isbn, language, description, target, compile, print, manuscript
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        author = try container.decode(String.self, forKey: .author)
        // Absent in any project.json written before §5's mode picker existed — those
        // projects were all Git mode, so that's the correct default, not just a
        // convenient one.
        versionControl = try container.decodeIfPresent(VersionControlMode.self, forKey: .versionControl) ?? .git
        series = try container.decode(Series.self, forKey: .series)
        copyrightYear = try container.decode(Int.self, forKey: .copyrightYear)
        publisher = try container.decode(String.self, forKey: .publisher)
        isbn = try container.decode(String.self, forKey: .isbn)
        language = try container.decode(String.self, forKey: .language)
        description = try container.decode(String.self, forKey: .description)
        target = try container.decode(Target.self, forKey: .target)
        compile = try container.decode(Compile.self, forKey: .compile)
        print = try container.decode(Print.self, forKey: .print)
        manuscript = try container.decodeIfPresent(Manuscript.self, forKey: .manuscript) ?? Manuscript()
    }
}
