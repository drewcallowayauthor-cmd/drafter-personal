import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    /// Drag-to-reorder for `Section("Manuscript")`'s chapters.
    func moveChapters(from source: IndexSet, to destination: Int) {
        guard let tree = projectViewModel.binderTree else { return }
        var urls = tree.manuscript.map(\.url)
        urls.move(fromOffsets: source, toOffset: destination)
        Task { await projectViewModel.reorder(orderedURLs: urls) }
    }

    /// A scene's context menu: rename/delete, plus "Move to Chapter" — a
    /// non-drag fallback for moving a scene into another chapter (§8.2), since
    /// drag-and-drop alone can't reach a collapsed or off-screen chapter.
    @ViewBuilder
    func sceneContextMenu(scene: SceneNode, currentChapter: ChapterNode) -> some View {
        binderRenameDeleteMenu(url: scene.url, currentTitle: scene.displayName, isChapter: false)
        if let tree = projectViewModel.binderTree {
            let otherChapters = tree.manuscript.filter { !$0.isLooseFile && $0.url != currentChapter.url }
            if !otherChapters.isEmpty {
                Menu("Move to Chapter") {
                    ForEach(otherChapters) { target in
                        Button(target.displayName) {
                            Task {
                                await projectViewModel.moveScene(scene.url, toChapterDirectory: target.url, before: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Drop target for a scene row (§8.2's drag-to-reorder/cross-chapter move):
    /// drops land immediately before the row dropped on, in that row's chapter —
    /// which may be a different chapter than the dragged scene's current one.
    func handleSceneDrop(_ items: [String], into chapter: ChapterNode, before targetScene: SceneNode?) -> Bool {
        guard !chapter.isLooseFile, let urlString = items.first, let sourceURL = URL(string: urlString) else {
            return false
        }
        Task { await projectViewModel.moveScene(sourceURL, toChapterDirectory: chapter.url, before: targetScene?.url) }
        return true
    }

    /// Drag-to-reorder for a flat section (Front Matter, Back Matter, Notes).
    func moveFlatSection(_ scenes: [SceneNode], from source: IndexSet, to destination: Int) {
        var urls = scenes.map(\.url)
        urls.move(fromOffsets: source, toOffset: destination)
        Task { await projectViewModel.reorder(orderedURLs: urls) }
    }

    /// ⌥⌘⇧N's target chapter: whichever chapter contains the current selection (a
    /// scene, or the chapter row itself), falling back to the last chapter so the
    /// shortcut still does something sensible with a loose-file chapter, a Front/Back
    /// Matter/Notes item, or nothing at all selected. `nil` only when the manuscript
    /// has no real (non-loose-file) chapter to add a scene to yet.
    var chapterURLForNewScene: URL? {
        guard let tree = projectViewModel.binderTree else { return nil }
        let chapters = tree.manuscript.filter { !$0.isLooseFile }
        if let selectedSceneURL {
            if let ownChapter = chapters.first(where: { $0.url == selectedSceneURL }) {
                return ownChapter.url
            }
            if let containingChapter = chapters.first(where: { chapter in
                chapter.scenes.contains { $0.url == selectedSceneURL }
            }) {
                return containingChapter.url
            }
        }
        return chapters.last?.url
    }

    /// ⌘⌫'s target: the same confirmation dialog the context menu's "Delete…" already
    /// uses, for whichever binder row is currently selected — a no-op with nothing
    /// selected, rather than guessing.
    func requestDeleteSelection() {
        guard let url = selectedSceneURL, let tree = projectViewModel.binderTree else { return }
        if let chapter = tree.manuscript.first(where: { $0.url == url }) {
            deleteTarget = BinderDeleteTarget(url: chapter.url, displayName: chapter.displayName, isChapter: true)
            return
        }
        let flatSections = [tree.frontMatter, tree.backMatter, tree.notes] + tree.manuscript.map(\.scenes)
        for section in flatSections {
            if let scene = section.first(where: { $0.url == url }) {
                deleteTarget = BinderDeleteTarget(url: scene.url, displayName: scene.displayName, isChapter: false)
                return
            }
        }
    }

    /// Finder-drop handler for the Notes section: copies every dropped file in as-is.
    func handleNotesDrop(_ urls: [URL]) -> Bool {
        guard let notesDirectoryURL, !urls.isEmpty else { return false }
        Task {
            for url in urls {
                _ = await projectViewModel.importFile(from: url, into: notesDirectoryURL)
            }
            toastCenter.show(urls.count == 1 ? "Added to Notes" : "Added \(urls.count) files to Notes")
        }
        return true
    }

    /// Finder-drop handler for the Front Matter section: the first dropped image
    /// becomes the book cover (§4.5). Non-image drops are ignored rather than added
    /// as a binder row, since Front Matter is template-generated `.md` only.
    func handleCoverImageDrop(_ urls: [URL]) -> Bool {
        guard
            let imageURL = urls.first(where: { url in
                (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
            })
        else {
            toastCenter.show("Only image files can be set as the cover")
            return false
        }
        Task {
            if await projectViewModel.setCoverImage(from: imageURL) {
                toastCenter.show("Cover image set — see Front Matter")
            }
        }
        return true
    }

    @ViewBuilder
    func regenerateMenuItem(for scene: SceneNode) -> some View {
        if let template = FrontBackMatterTemplate.matching(filename: scene.url.lastPathComponent) {
            Button("Regenerate from Template") {
                regenerateConfirmation = (template, scene.displayName)
            }
        }
    }
}
