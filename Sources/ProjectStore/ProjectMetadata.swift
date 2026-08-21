import Foundation

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
            sceneSeparator: String = "* * *",
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

        /// Defaults measured off a real compiled print PDF (Scrivener export of a
        /// finished novel) rather than assumed: Palatino at 11.5pt with ~1.46em leading
        /// (16.8pt line pitch), and chapters starting on the next page regardless of
        /// recto/verso — that reference never forces a blank page to keep chapters odd.
        public init(
            trimSize: String = "5x8",
            bodyFont: String = "Palatino",
            bodyPointSize: Double = 11.5,
            leading: Double = 1.46,
            chapterOpensOn: String = "either"
        ) {
            self.trimSize = trimSize
            self.bodyFont = bodyFont
            self.bodyPointSize = bodyPointSize
            self.leading = leading
            self.chapterOpensOn = chapterOpensOn
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
        print: Print = Print()
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
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, subtitle, author, versionControl, series, copyrightYear,
            publisher, isbn, language, description, target, compile, print
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
    }
}
