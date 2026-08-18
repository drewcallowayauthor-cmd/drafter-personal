import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

/// The Binder/Editor layout (§8.1), built up in M1 slices. Inspector pane comes later.
struct ContentView: View {
    @State private var projectViewModel = ProjectViewModel()
    @State private var sceneEditor = SceneEditorViewModel()
    @State private var isImporterPresented = false
    @State private var selectedSceneURL: URL?

    var body: some View {
        NavigationSplitView {
            binderList
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem {
                Button("Open Project…") { isImporterPresented = true }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await projectViewModel.open(root: url) }
            }
        }
        .onChange(of: selectedSceneURL) { _, newURL in
            // Chapter folder rows are implicitly selectable too (ChapterNode is
            // Identifiable, so List infers a tag from its id even without an explicit
            // .tag()) — only actually open something for a real scene/document.
            if let newURL, isOpenableScene(newURL) {
                sceneEditor.open(url: newURL)
            } else {
                sceneEditor.close()
            }
        }
        .task { await openDebugProjectIfRequested() }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var binderList: some View {
        if let tree = projectViewModel.binderTree {
            List(selection: $selectedSceneURL) {
                Section("Manuscript") {
                    ForEach(tree.manuscript) { chapter in
                        if chapter.isLooseFile {
                            Text(chapter.displayName).tag(chapter.url)
                        } else {
                            DisclosureGroup(chapter.displayName) {
                                ForEach(chapter.scenes) { scene in
                                    Text(scene.displayName).tag(scene.url)
                                }
                            }
                        }
                    }
                }
                if !tree.frontMatter.isEmpty {
                    Section("Front Matter") {
                        ForEach(tree.frontMatter) { Text($0.displayName).tag($0.url) }
                    }
                }
                if !tree.backMatter.isEmpty {
                    Section("Back Matter") {
                        ForEach(tree.backMatter) { Text($0.displayName).tag($0.url) }
                    }
                }
                if !tree.notes.isEmpty {
                    Section("Notes") {
                        ForEach(tree.notes) { Text($0.displayName).tag($0.url) }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "book.closed",
                description: Text("Open a project folder to browse its manuscript.")
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let error = sceneEditor.errorMessage {
            ContentUnavailableView("Couldn't Open Scene", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if sceneEditor.document != nil {
            SceneTextView(text: sceneBodyBinding)
        } else if let error = projectViewModel.errorMessage {
            ContentUnavailableView("Couldn't Open Project", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let metadata = projectViewModel.metadata {
            VStack(alignment: .leading, spacing: 8) {
                Text(metadata.title).font(.largeTitle)
                if !metadata.subtitle.isEmpty {
                    Text(metadata.subtitle).font(.title3).foregroundStyle(.secondary)
                }
                Text(metadata.author).foregroundStyle(.secondary)
            }
            .padding()
        } else {
            Text("Drafter").font(.largeTitle).foregroundStyle(.secondary)
        }
    }

    /// Dev-only convenience for visually verifying UI changes without clicking through
    /// the picker: `DRAFTER_DEBUG_PROJECT_PATH=/path/to/project swift run`.
    private func openDebugProjectIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["DRAFTER_DEBUG_PROJECT_PATH"] else { return }
        await projectViewModel.open(root: URL(fileURLWithPath: path))
        if let firstScene = projectViewModel.binderTree?.manuscript.first(where: { !$0.isLooseFile })?.scenes.first {
            selectedSceneURL = firstScene.url
        }
    }

    private func isOpenableScene(_ url: URL) -> Bool {
        guard let tree = projectViewModel.binderTree else { return false }
        let inManuscript = tree.manuscript.contains { chapter in
            (chapter.isLooseFile && chapter.url == url) || chapter.scenes.contains { $0.url == url }
        }
        return inManuscript
            || tree.frontMatter.contains { $0.url == url }
            || tree.backMatter.contains { $0.url == url }
            || tree.notes.contains { $0.url == url }
    }

    private var sceneBodyBinding: Binding<String> {
        Binding(
            get: { sceneEditor.document?.body ?? "" },
            set: { sceneEditor.updateBody($0) }
        )
    }
}

#Preview {
    ContentView()
}
