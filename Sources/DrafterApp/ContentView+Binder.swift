import AppKit
import ProjectStore
import SwiftUI

extension ContentView {
    @ViewBuilder
    var binderList: some View {
        if let tree = projectViewModel.binderTree {
            List(selection: $selectedSceneURL) {
                Section("Manuscript") {
                    ForEach(tree.manuscript) { chapter in
                        if chapter.isLooseFile {
                            Text(chapter.displayName).tag(chapter.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: chapter.url))
                                .contextMenu {
                                    binderRenameDeleteMenu(
                                        url: chapter.url, currentTitle: chapter.displayName, isChapter: true
                                    )
                                }
                        } else {
                            DisclosureGroup(isExpanded: isChapterExpandedBinding(chapter.url)) {
                                ForEach(chapter.scenes) { scene in
                                    Text(scene.displayName).tag(scene.url)
                                        .foregroundStyle(Theme.Color.text)
                                        .listRowBackground(rowBackground(for: scene.url))
                                        .contextMenu { sceneContextMenu(scene: scene, currentChapter: chapter) }
                                        .draggable(scene.url.absoluteString)
                                        .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                                            handleSceneDrop(items, into: chapter, before: scene)
                                        }
                                }
                            } label: {
                                Text(chapter.displayName)
                            }
                            .foregroundStyle(Theme.Color.text)
                            .contextMenu {
                                Button("New Scene…") { newSceneChapterURL = chapter.url }
                                Divider()
                                binderRenameDeleteMenu(
                                    url: chapter.url, currentTitle: chapter.displayName, isChapter: true
                                )
                            }
                        }
                    }
                    .onMove(perform: moveChapters)
                    Button("+ Chapter") { isNewChapterSheetPresented = true }
                        .buttonStyle(.nocturneGhost)
                        .frame(height: 24)
                        .listRowBackground(SwiftUI.Color.clear)
                }
                if !tree.frontMatter.isEmpty || coverImageURL != nil {
                    Section("Front Matter") {
                        coverImageRow
                        ForEach(tree.frontMatter) { scene in
                            Text(scene.displayName).tag(scene.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: scene.url))
                                .contextMenu {
                                    regenerateMenuItem(for: scene)
                                    binderRenameDeleteMenu(
                                        url: scene.url, currentTitle: scene.displayName, isChapter: false
                                    )
                                }
                        }
                        .onMove { source, destination in
                            moveFlatSection(tree.frontMatter, from: source, to: destination)
                        }
                    }
                    // Dropping an image file here sets it as the book cover (§4.5's
                    // `compile.coverImage`) rather than adding a binder row — the cover
                    // lives in `Resources/`, not as a Front Matter scene.
                    .dropDestination(for: URL.self) { urls, _ in handleCoverImageDrop(urls) }
                }
                if !tree.backMatter.isEmpty {
                    Section("Back Matter") {
                        ForEach(tree.backMatter) { scene in
                            Text(scene.displayName).tag(scene.url)
                                .foregroundStyle(Theme.Color.text)
                                .listRowBackground(rowBackground(for: scene.url))
                                .contextMenu {
                                    regenerateMenuItem(for: scene)
                                    binderRenameDeleteMenu(
                                        url: scene.url, currentTitle: scene.displayName, isChapter: false
                                    )
                                }
                        }
                        .onMove { source, destination in
                            moveFlatSection(tree.backMatter, from: source, to: destination)
                        }
                    }
                }
                // Always visible (unlike Front/Back Matter, which only appear once
                // seeded) so "+ Note" and the Finder-drop target are always reachable —
                // Notes has no template scaffolding to seed it at project creation.
                Section("Notes") {
                    ForEach(tree.notes) { note in
                        noteRow(note)
                    }
                    .onMove { source, destination in moveFlatSection(tree.notes, from: source, to: destination) }
                    Button("+ Note") { isNewNoteSheetPresented = true }
                        .buttonStyle(.nocturneGhost)
                        .frame(height: 24)
                        .listRowBackground(SwiftUI.Color.clear)
                }
                // Reference documents (PDFs, images, anything) dropped from Finder are
                // copied in as-is, keeping their own extension — unlike scenes, which
                // are always created as `.md`.
                .dropDestination(for: URL.self) { urls, _ in handleNotesDrop(urls) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bg)
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "book.closed",
                description: Text("Open a project folder to browse its manuscript.")
            )
        }
    }

    /// The accent-800 selected-row background the handoff specifies — `List` selection's
    /// system highlight is overridden per-row rather than relying on the platform default.
    func rowBackground(for url: URL) -> SwiftUI.Color {
        selectedSceneURL == url ? Theme.Color.accent800 : .clear
    }

    /// Shared "Rename…"/"Delete…" pair for every binder row (§8.2).
    @ViewBuilder
    func binderRenameDeleteMenu(url: URL, currentTitle: String, isChapter: Bool) -> some View {
        Button("Rename…") { renameTarget = BinderRenameTarget(url: url, currentTitle: currentTitle) }
        Button(isChapter ? "Delete Chapter…" : "Delete…", role: .destructive) {
            deleteTarget = BinderDeleteTarget(url: url, displayName: currentTitle, isChapter: isChapter)
        }
    }

    func isChapterExpandedBinding(_ chapterURL: URL) -> Binding<Bool> {
        Binding(
            get: { expandedChapterURLs.contains(chapterURL) },
            set: { isExpanded in
                if isExpanded { expandedChapterURLs.insert(chapterURL) } else { expandedChapterURLs.remove(chapterURL) }
            }
        )
    }

    /// A Notes row: a markdown note opens in the editor like any other scene; a
    /// dropped-in reference document (PDF, image, anything non-markdown) instead
    /// shows an "Open"/"Show in Finder" detail pane (§ attachmentDetail below) since
    /// the editor can't display it.
    @ViewBuilder
    func noteRow(_ note: SceneNode) -> some View {
        Label(note.displayName, systemImage: isMarkdownFile(note.url) ? "doc.text" : "paperclip")
            .tag(note.url)
            .foregroundStyle(Theme.Color.text)
            .listRowBackground(rowBackground(for: note.url))
            .contextMenu {
                if !isMarkdownFile(note.url) {
                    Button("Open") { NSWorkspace.shared.open(note.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                    Divider()
                }
                binderRenameDeleteMenu(url: note.url, currentTitle: note.displayName, isChapter: false)
            }
    }

    func isMarkdownFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "md"
    }

    /// The book cover's on-disk location (§4.5's `compile.coverImage`), or `nil` if
    /// none has been set yet or the file it points at no longer exists.
    var coverImageURL: URL? {
        guard let root = projectViewModel.workingTreeRoot, let path = projectViewModel.metadata?.compile.coverImage,
              !path.isEmpty
        else { return nil }
        let url = root.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
        return exists ? url : nil
    }

    /// A pinned first row in Front Matter showing the current cover (or a hint that
    /// there isn't one yet) — otherwise a dropped-in cover has no visible trace
    /// anywhere in the binder, since it lives in `Resources/`, not as a scene.
    @ViewBuilder
    var coverImageRow: some View {
        if let coverImageURL {
            HStack(spacing: 8) {
                // A thumbnail that fails to decode (an unusual format, a corrupt
                // file) must not hide the row's only "Remove" affordance behind it —
                // fall back to a generic icon rather than treating decode failure as
                // "no cover set".
                if let nsImage = NSImage(contentsOf: coverImageURL) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.Color.textMuted)
                }
                Text("Cover: \(coverImageURL.lastPathComponent)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
                // A visible button, not just a context menu — a lone right-click-only
                // affordance on an otherwise static row is easy to miss entirely.
                Button {
                    Task { await projectViewModel.removeCoverImage() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.textMuted)
                .help("Remove Cover Image")
            }
            .contentShape(Rectangle())
            .listRowBackground(SwiftUI.Color.clear)
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([coverImageURL]) }
                Button("Remove Cover Image", role: .destructive) { Task { await projectViewModel.removeCoverImage() } }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.Color.textMuted)
                Text("No cover image — drop one here")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
            }
            .listRowBackground(SwiftUI.Color.clear)
        }
    }

    var notesDirectoryURL: URL? {
        projectViewModel.workingTreeRoot?.appendingPathComponent("Notes")
    }
}
