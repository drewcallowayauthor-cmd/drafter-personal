import DrafterCore
import GitService
import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

/// The Binder/Editor/Inspector layout (§8.1). Inspector currently holds History (§5.8);
/// Scene and Targets sections are later additions to the same pane.
struct ContentView: View {
    @State private var projectViewModel = ProjectViewModel()
    @State private var sceneEditor = SceneEditorViewModel()
    @State private var historyViewModel: HistoryViewModel?
    @State private var targetsViewModel = TargetsViewModel()
    @State private var isImporterPresented = false
    @State private var isInspectorPresented = true
    @State private var selectedSceneURL: URL?
    @State private var isTypewriterScrollingEnabled = true
    @State private var regenerateConfirmation: (template: FrontBackMatterTemplate, displayName: String)?
    @State private var frontBackMatterError: String?
    @State private var isMetadataEditorPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            binderList
        } detail: {
            detail
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspector
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                saveStatus
            }
            ToolbarItem {
                Toggle("Typewriter", isOn: $isTypewriterScrollingEnabled)
            }
            ToolbarItem {
                Button("Generate Front/Back Matter") { generateMissingFrontBackMatter() }
                    .disabled(projectViewModel.metadata == nil)
            }
            ToolbarItem {
                Button("Project Settings…") { isMetadataEditorPresented = true }
                    .disabled(projectViewModel.metadata == nil)
            }
            ToolbarItem {
                Button("Open Project…") { isImporterPresented = true }
            }
            ToolbarItem {
                Button { isInspectorPresented.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .confirmationDialog(
            "Regenerate “\(regenerateConfirmation?.displayName ?? "")” from Template?",
            isPresented: Binding(get: { regenerateConfirmation != nil }, set: { if !$0 { regenerateConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { performRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites any hand edits with the standard template content.")
        }
        .alert("Couldn't Generate Front/Back Matter", isPresented: Binding(get: { frontBackMatterError != nil }, set: { if !$0 { frontBackMatterError = nil } })) {
            Button("OK") {}
        } message: {
            Text(frontBackMatterError ?? "")
        }
        .sheet(isPresented: $isMetadataEditorPresented) {
            if let metadata = projectViewModel.metadata {
                ProjectMetadataEditor(
                    metadata: metadata,
                    onSave: { updated in
                        Task { await projectViewModel.save(metadata: updated) }
                        isMetadataEditorPresented = false
                    },
                    onCancel: { isMetadataEditorPresented = false }
                )
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
        .onChange(of: scenePhase) { _, newPhase in
            // "App loses focus" (§8.3 point 9, §5.4) — flush the pending disk write
            // immediately rather than waiting out its debounce, then commit immediately
            // too rather than waiting out the separate 90s commit debounce.
            if newPhase != .active {
                sceneEditor.saveNow()
                Task { await projectViewModel.autocommitScheduler?.flush(trigger: .focusLost) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drafterRequestCheckpoint)) { _ in
            sceneEditor.saveNow()
            Task { await projectViewModel.autocommitScheduler?.flush(trigger: .checkpoint(label: nil)) }
        }
        .onChange(of: projectViewModel.workingTreeRoot) { _, _ in
            historyViewModel = projectViewModel.gitService.map { HistoryViewModel(gitService: $0) }
            targetsViewModel.resetSession()
        }
        .onChange(of: projectViewModel.binderTree) { _, newTree in
            if let newTree {
                targetsViewModel.recalculate(binderTree: newTree)
            }
        }
        .onChange(of: historyViewModel?.restoredFileURL) { _, newValue in
            guard newValue != nil else { return }
            Task {
                await projectViewModel.refresh()
                historyViewModel?.clearRestoredFileURL()
            }
        }
        .task {
            // Reads projectViewModel.autocommitScheduler dynamically on each save
            // rather than capturing today's value, since it's created after the
            // project (and its repo) finishes opening.
            sceneEditor.onSaved = { wordDelta in
                projectViewModel.autocommitScheduler?.recordActivity(wordDelta: wordDelta)
                targetsViewModel.recordSessionActivity(wordDelta: wordDelta)
            }
            await openDebugProjectIfRequested()
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var saveStatus: some View {
        if let document = sceneEditor.document {
            Text(document.isDirty ? "Unsaved" : "Saved")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if projectViewModel.metadata != nil {
            VStack(spacing: 0) {
                TargetsPanel(
                    totals: targetsViewModel.totals,
                    targetWords: projectViewModel.metadata?.target.words ?? 0,
                    sessionWords: targetsViewModel.sessionWords
                )
                Divider()
                historySection
            }
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "chart.bar",
                description: Text("Open a project to see word count targets and history.")
            )
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let historyViewModel, let sceneURL = selectedSceneURL, isOpenableScene(sceneURL),
            let workingTree = projectViewModel.workingTreeRoot
        {
            HistoryPanel(
                history: historyViewModel,
                sceneURL: sceneURL,
                workingTree: workingTree,
                currentBody: sceneEditor.document?.body ?? ""
            )
        } else {
            ContentUnavailableView(
                "No Scene Selected",
                systemImage: "clock",
                description: Text("Select a scene to see its history.")
            )
        }
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
                        ForEach(tree.frontMatter) { scene in
                            Text(scene.displayName).tag(scene.url).contextMenu {
                                regenerateMenuItem(for: scene)
                            }
                        }
                    }
                }
                if !tree.backMatter.isEmpty {
                    Section("Back Matter") {
                        ForEach(tree.backMatter) { scene in
                            Text(scene.displayName).tag(scene.url).contextMenu {
                                regenerateMenuItem(for: scene)
                            }
                        }
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
            SceneTextView(text: sceneBodyBinding, isTypewriterScrollingEnabled: isTypewriterScrollingEnabled)
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

    @ViewBuilder
    private func regenerateMenuItem(for scene: SceneNode) -> some View {
        if let template = FrontBackMatterTemplate.matching(filename: scene.url.lastPathComponent) {
            Button("Regenerate from Template") {
                regenerateConfirmation = (template, scene.displayName)
            }
        }
    }

    private func generateMissingFrontBackMatter() {
        guard let metadata = projectViewModel.metadata, let root = projectViewModel.workingTreeRoot else { return }
        do {
            _ = try FrontBackMatterService.generateMissing(metadata: metadata, workingTree: root, fileWriter: LiveAtomicFileWriter())
            Task { await projectViewModel.refresh() }
        } catch {
            frontBackMatterError = String(describing: error)
        }
    }

    private func performRegenerate() {
        defer { regenerateConfirmation = nil }
        guard let pending = regenerateConfirmation, let metadata = projectViewModel.metadata,
            let root = projectViewModel.workingTreeRoot
        else { return }
        do {
            try FrontBackMatterService.regenerate(
                template: pending.template,
                metadata: metadata,
                workingTree: root,
                fileWriter: LiveAtomicFileWriter()
            )
            if let sceneURL = selectedSceneURL, sceneURL.lastPathComponent == pending.template.filename {
                sceneEditor.open(url: sceneURL)
            }
        } catch {
            frontBackMatterError = String(describing: error)
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
