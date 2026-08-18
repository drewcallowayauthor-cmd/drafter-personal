import Foundation
import ProjectStore

/// One chapter's word count, for the Targets panel's per-chapter breakdown (§8.4).
public struct ChapterWordCount: Sendable, Equatable {
    public let chapter: String
    public let words: Int

    public init(chapter: String, words: Int) {
        self.chapter = chapter
        self.words = words
    }
}

public struct WordCountTotals: Sendable, Equatable {
    public let project: Int
    public let perChapter: [ChapterWordCount]

    public init(project: Int, perChapter: [ChapterWordCount]) {
        self.project = project
        self.perChapter = perChapter
    }
}

/// Aggregates §8.4's Targets panel numbers: project and per-chapter word counts across
/// the whole manuscript. Unlike `ManuscriptAssembler`, this counts every scene
/// regardless of `compile: false` — Targets tracks writing progress, not export output,
/// so an excluded scene's words still count toward "words written."
public enum WordCountAggregator {
    public static func aggregate(binderTree: BinderTree, read: SceneReader) throws -> WordCountTotals {
        var perChapter: [ChapterWordCount] = []
        var projectTotal = 0

        for chapter in binderTree.manuscript {
            let sceneURLs = chapter.isLooseFile ? [chapter.url] : chapter.scenes.map(\.url)
            var chapterTotal = 0
            for url in sceneURLs {
                let body = SceneFrontMatter.parse(try read(url)).body
                chapterTotal += WordCounter.count(body)
            }
            perChapter.append(ChapterWordCount(chapter: chapter.displayName, words: chapterTotal))
            projectTotal += chapterTotal
        }

        return WordCountTotals(project: projectTotal, perChapter: perChapter)
    }
}
