import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

/// M0 placeholder — a read-only binder list proving the ProjectStore wiring end to end.
/// Replaced by the full Binder/Editor/Inspector layout (§8.1) once editing lands.
struct ContentView: View {
    @State private var viewModel = ProjectViewModel()
    @State private var isImporterPresented = false

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
                Task { await viewModel.open(root: url) }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var binderList: some View {
        if let tree = viewModel.binderTree {
            List {
                Section("Manuscript") {
                    ForEach(tree.manuscript) { chapter in
                        if chapter.isLooseFile {
                            Text(chapter.displayName)
                        } else {
                            DisclosureGroup(chapter.displayName) {
                                ForEach(chapter.scenes) { scene in
                                    Text(scene.displayName)
                                }
                            }
                        }
                    }
                }
                if !tree.frontMatter.isEmpty {
                    Section("Front Matter") {
                        ForEach(tree.frontMatter) { Text($0.displayName) }
                    }
                }
                if !tree.backMatter.isEmpty {
                    Section("Back Matter") {
                        ForEach(tree.backMatter) { Text($0.displayName) }
                    }
                }
                if !tree.notes.isEmpty {
                    Section("Notes") {
                        ForEach(tree.notes) { Text($0.displayName) }
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
        if let error = viewModel.errorMessage {
            ContentUnavailableView("Couldn't Open Project", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let metadata = viewModel.metadata {
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
}

#Preview {
    ContentView()
}
