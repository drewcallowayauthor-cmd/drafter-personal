import DrafterCore
import SwiftUI

/// §5.8's History panel: commits touching the open scene, with relative time, word
/// delta, and machine name. Clicking a commit shows the two-pane diff against the
/// current in-editor text; the context menu offers "Restore as Copy" (§5.8's primary
/// restore action) directly.
struct HistoryPanel: View {
    let history: HistoryViewModel
    let sceneURL: URL
    let workingTree: URL
    let currentBody: String

    @State private var diffPresentation: DiffPresentation?
    @State private var isDiffLoading = false

    private struct DiffPresentation: Identifiable {
        let id: String
        let entry: CommitLogEntry
        let lines: [SceneDiffLine]
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(Theme.Font.heading(15))
                .foregroundStyle(Theme.Color.text)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .task(id: sceneURL) {
            await history.load(sceneURL: sceneURL, workingTree: workingTree)
        }
        .overlay {
            if history.isRestoring || isDiffLoading {
                ProgressView().controlSize(.small)
            }
        }
        .alert(
            "Couldn't Complete Action",
            isPresented: Binding(
                get: { history.actionErrorMessage != nil },
                set: { if !$0 { history.clearActionErrorMessage() } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(history.actionErrorMessage ?? "")
        }
        .sheet(item: $diffPresentation) { presentation in
            VStack(spacing: 0) {
                DiffView(
                    lines: presentation.lines,
                    oldLabel: "\(presentation.entry.subject) (" +
                        "\(Self.relativeFormatter.localizedString(for: presentation.entry.date, relativeTo: .now)))",
                    newLabel: "Current"
                )
                Rectangle().fill(Theme.Color.divider).frame(height: 1)
                HStack {
                    Spacer()
                    Button("Close") { diffPresentation = nil }
                        .buttonStyle(.nocturneSecondary)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(16)
            }
            .background(Theme.Color.surface)
            .nocturneSheetPresentation()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = history.errorMessage {
            ContentUnavailableView(
                "Couldn't Load History", systemImage: "exclamationmark.triangle", description: Text(error)
            )
        } else if history.isLoading {
            // Deliberately blank rather than "No History Yet" — that empty state is
            // only accurate once the fetch for the newly selected scene has actually
            // come back; showing it during the gap flashed wrong info on every scene
            // switch. Explicitly sized rather than a bare `Color.clear`, which
            // collapses to zero height and made the "History" label above jump as
            // the panel resized out and back in on every switch.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if history.entries.isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Commits touching this scene will show up here.")
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(history.entries, id: \.sha) { entry in
                        row(for: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await showDiff(for: entry) }
                            }
                            .contextMenu {
                                Button("Restore as Copy") {
                                    Task {
                                        await history.restoreAsCopy(
                                            entry: entry, sceneURL: sceneURL, workingTree: workingTree
                                        )
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func showDiff(for entry: CommitLogEntry) async {
        isDiffLoading = true
        defer { isDiffLoading = false }
        if let lines = await history.diffLines(
            against: entry,
            sceneURL: sceneURL,
            workingTree: workingTree,
            currentBody: currentBody
        ) {
            diffPresentation = DiffPresentation(id: entry.sha, entry: entry, lines: lines)
        }
    }

    private func row(for entry: CommitLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.subject)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.text)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(Self.relativeFormatter.localizedString(for: entry.date, relativeTo: .now))
                if !entry.machineName.isEmpty {
                    Text("·")
                    Text(entry.machineName)
                }
                if let wordDelta = CommitSubjectWordDelta.parse(entry.subject) {
                    Text("·")
                    Text(wordDelta >= 0 ? "+\(wordDelta)" : "\(wordDelta)")
                        .foregroundStyle(wordDelta >= 0 ? Theme.Color.accent200 : .red)
                }
            }
            .font(Theme.Font.body(11))
            .foregroundStyle(Theme.Color.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
