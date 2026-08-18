import ProjectStore
import SwiftUI

/// Editor for `project.json` (§4.5, §10). Works on a local draft; nothing is written
/// until Save, matching `project.json`'s description as "rarely written" — no
/// autosave-on-every-keystroke here the way scene text gets.
struct ProjectMetadataEditor: View {
    @State private var draft: ProjectMetadata
    let onSave: (ProjectMetadata) -> Void
    let onCancel: () -> Void

    init(metadata: ProjectMetadata, onSave: @escaping (ProjectMetadata) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: metadata)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Book") {
                    TextField("Title", text: $draft.title)
                    TextField("Subtitle", text: $draft.subtitle)
                    TextField("Author", text: $draft.author)
                    TextField("Description", text: $draft.description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Series") {
                    TextField("Series Name", text: $draft.series.name)
                    TextField("Number in Series", text: seriesNumberText)
                }

                Section("Publishing") {
                    Stepper("Copyright Year: \(String(draft.copyrightYear))", value: $draft.copyrightYear, in: 1900...2100)
                    TextField("Publisher", text: $draft.publisher)
                    TextField("ISBN", text: $draft.isbn)
                    TextField("Language", text: $draft.language)
                }

                Section("Target") {
                    TextField("Word Count Goal", text: targetWordsText)
                }

                Section("Compile") {
                    TextField("Chapter Title Format", text: $draft.compile.chapterTitleFormat)
                    TextField("Scene Separator", text: $draft.compile.sceneSeparator)
                    Toggle("Include Front Matter", isOn: $draft.compile.includeFrontMatter)
                    Toggle("Include Back Matter", isOn: $draft.compile.includeBackMatter)
                }

                Section("Print") {
                    TextField("Trim Size", text: $draft.print.trimSize)
                    TextField("Body Font", text: $draft.print.bodyFont)
                    TextField("Chapter Opens On", text: $draft.print.chapterOpensOn)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 620)
    }

    private var seriesNumberText: Binding<String> {
        Binding(
            get: { draft.series.number.map(String.init) ?? "" },
            set: { draft.series.number = Int($0) }
        )
    }

    private var targetWordsText: Binding<String> {
        Binding(
            get: { String(draft.target.words) },
            set: { draft.target.words = Int($0) ?? draft.target.words }
        )
    }
}
