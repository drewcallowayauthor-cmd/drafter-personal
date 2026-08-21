import Foundation

/// The New Project sheet's "Novel" vs "Short Story" choice — the only thing it
/// actually changes is the new project's default `chapterTitleFormat` (§4.5). A short
/// story's "chapters" are conventionally just numbered scene breaks ("1", "2", "3"…)
/// rather than "Chapter N" — the existing chapter-folder-per-section structure works
/// unchanged for either, so this needs no new manuscript scaffolding, just a different
/// starting format the writer is free to edit afterward like any other compile setting.
enum ManuscriptTemplate: String, CaseIterable, Identifiable {
    case novel = "Novel"
    case shortStory = "Short Story"

    var id: String { rawValue }

    var defaultChapterTitleFormat: String {
        switch self {
        case .novel: return "Chapter {n}"
        case .shortStory: return "{n}"
        }
    }

    var description: String {
        switch self {
        case .novel: return "Sections are numbered chapters (\u{201c}Chapter 1\u{201d})."
        case .shortStory: return "Sections are bare numbered scene breaks (\u{201c}1\u{201d}) instead of chapters."
        }
    }
}
