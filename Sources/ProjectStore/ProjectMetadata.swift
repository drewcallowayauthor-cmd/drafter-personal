import Foundation

/// Book-level settings, §4.5. Mirrors `project.json`'s shape exactly so `Codable`
/// synthesis needs no custom coding keys.
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

        public init(
            trimSize: String = "5x8",
            bodyFont: String = "EB Garamond",
            bodyPointSize: Double = 11.0,
            leading: Double = 1.35,
            chapterOpensOn: String = "recto"
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
}
