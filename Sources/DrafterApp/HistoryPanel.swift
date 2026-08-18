import GitService
import SwiftUI

/// §5.8's History panel: commits touching the open scene, with relative time, word
/// delta, and machine name, plus a "Restore as copy" action per commit. The two-pane
/// diff view §5.8 also specifies is a natural follow-up, not built here.
struct HistoryPanel: View {
    let history: HistoryViewModel
    let sceneURL: URL
    let workingTree: URL

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.headline)
                .padding([.horizontal, .top])

            if let error = history.errorMessage {
                ContentUnavailableView("Couldn't Load History", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if history.entries.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock",
                    description: Text("Commits touching this scene will show up here.")
                )
            } else {
                List(history.entries, id: \.sha) { entry in
                    row(for: entry)
                        .contextMenu {
                            Button("Restore as Copy") {
                                Task { await history.restoreAsCopy(entry: entry, sceneURL: sceneURL, workingTree: workingTree) }
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .task(id: sceneURL) {
            await history.load(sceneURL: sceneURL, workingTree: workingTree)
        }
        .overlay {
            if history.isRestoring {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func row(for entry: CommitLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.subject)
                .font(.system(size: 12, weight: .medium))
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
                        .foregroundStyle(wordDelta >= 0 ? .green : .red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
