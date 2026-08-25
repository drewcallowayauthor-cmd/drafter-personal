import DrafterCore
import Foundation
import ProjectStore

/// Binder CRUD, search/replace, and metadata-save operations for `ProjectViewModel`,
/// split out to keep the main file's file/type-body lengths under SwiftLint's limits.
extension ProjectViewModel {
    func refresh() async {
        guard let project else { return }
        do {
            try await project.refreshBinderTree()
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §8.2's "New Chapter" — returns the seeded scene's URL on success so
    /// `ContentView` can select and open it immediately.
    func createChapter(title: String) async -> URL? {
        guard let project else { return nil }
        do {
            let sceneURL = try await project.createChapter(title: title, fileWriter: LiveAtomicFileWriter())
            binderTree = await project.binderTree
            return sceneURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's "New Scene" — `directory` is a chapter folder, or one of the flat
    /// FrontMatter/BackMatter/Notes sections.
    func createScene(title: String, in directory: URL) async -> URL? {
        guard let project else { return nil }
        do {
            let sceneURL = try await project.createScene(
                title: title, in: directory, fileWriter: LiveAtomicFileWriter()
            )
            binderTree = await project.binderTree
            return sceneURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's binder rename — returns the item's new URL on success so `ContentView`
    /// can follow a rename of the currently-open/selected scene.
    @discardableResult
    func rename(itemAt url: URL, to newTitle: String) async -> URL? {
        guard let project else { return nil }
        do {
            let newURL = try await project.rename(itemAt: url, to: newTitle)
            binderTree = await project.binderTree
            return newURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// §8.2's binder delete — removes a scene file or an entire chapter folder.
    func delete(itemAt url: URL) async {
        guard let project else { return }
        do {
            try await project.delete(itemAt: url)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §4.3/§8.2's drag-to-reorder — `orderedURLs` must all share one directory (a
    /// chapter's scenes, a flat section, or Manuscript's chapters).
    func reorder(orderedURLs: [URL]) async {
        guard let project else { return }
        do {
            try await project.reorder(orderedURLs: orderedURLs)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §8.2's cross-chapter drag — moves a scene into `chapterDirectory` (possibly
    /// its current one, for a same-chapter reorder), inserting it immediately
    /// before `targetURL`, or at the end when `targetURL` is `nil`.
    func moveScene(_ url: URL, toChapterDirectory chapterDirectory: URL, before targetURL: URL?) async {
        guard let project else { return }
        do {
            try await project.moveScene(at: url, toChapterDirectory: chapterDirectory, before: targetURL)
            binderTree = await project.binderTree
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drag-and-drop (or a future file picker) import of an external file into a flat
    /// binder section — currently Notes, which accepts any file type for reference
    /// documents. Returns the copy's URL so the caller can select it.
    func importFile(from sourceURL: URL, into directory: URL) async -> URL? {
        guard let project else { return nil }
        do {
            let importedURL = try await project.importFile(from: sourceURL, into: directory)
            binderTree = await project.binderTree
            return importedURL
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Sets the book cover from an external image (dropped onto Front Matter, or
    /// chosen from Settings) — copies it into `Resources/` and updates
    /// `compile.coverImage` (§4.5).
    @discardableResult
    func setCoverImage(from sourceURL: URL) async -> Bool {
        guard let project else { return false }
        do {
            _ = try await project.setCoverImage(from: sourceURL, fileWriter: LiveAtomicFileWriter())
            metadata = await project.metadata
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Deletes the current cover image file. Leaves `compile.coverImage`'s path as-is
    /// rather than clearing it — every consumer (export, the Front Matter cover row)
    /// already checks the file exists before using it, so a dangling path is harmless.
    func removeCoverImage() async {
        guard let workingTreeRoot, let metadata, !metadata.compile.coverImage.isEmpty else { return }
        errorMessage = nil
        do {
            try FileManager.default.removeItem(at: workingTreeRoot.appendingPathComponent(metadata.compile.coverImage))
        } catch {
            errorMessage = "Couldn't remove the cover image: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// §8.3 point 8's project-wide find (⇧⌘F).
    func search(options: ProjectSearchOptions) async -> [ProjectSearchMatch] {
        guard let project else { return [] }
        return await project.search(options: options)
    }

    /// Applies a batch of replacements. Returns the scene URLs actually rewritten so
    /// the caller can reload any of them that's currently open in the editor.
    @discardableResult
    func replace(matches: [ProjectSearchMatch], replacement: String) async -> Set<URL> {
        guard let project else { return [] }
        do {
            return try await project.replace(
                matches: matches, replacement: replacement, fileWriter: LiveAtomicFileWriter()
            )
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Saves an edited copy of `project.json` (§4.5) — the metadata editor works on a
    /// local draft and only calls this on explicit confirmation.
    @discardableResult
    func save(metadata: ProjectMetadata) async -> Bool {
        guard let project else { return false }
        do {
            try await project.save(metadata: metadata)
            self.metadata = metadata
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
