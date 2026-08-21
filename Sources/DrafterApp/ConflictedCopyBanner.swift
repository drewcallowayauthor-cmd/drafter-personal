import SnapshotService
import SwiftUI

/// §7.5: a non-blocking banner, not a modal sheet — Local-file mode has no merge
/// engine to gate on, so unlike Git mode's `ConflictSheet` this never stops the writer
/// from doing anything else. One row per suspected conflict copy.
struct ConflictedCopyBanner: View {
    let viewModel: ConflictedCopyViewModel

    @State private var compareTarget: ConflictedCopyDetector.Match?
    @State private var compareLines: [SceneDiffLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.matches, id: \.conflictedURL) { match in
                row(for: match)
                Divider()
            }
        }
        .background(.yellow.opacity(0.12))
        .alert(
            "Couldn't Complete Action",
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.clearActionErrorMessage() } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
        .sheet(item: $compareTarget) { _ in
            VStack(spacing: 0) {
                DiffView(lines: compareLines, oldLabel: "Original", newLabel: "Conflict Copy")
                Divider()
                HStack {
                    Spacer()
                    Button("Close") { compareTarget = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
        }
    }

    private func row(for match: ConflictedCopyDetector.Match) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A file may have synced with a conflict")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(match.conflictedURL.lastPathComponent) looks like a cloud-sync conflict copy of \(match.originalURL.lastPathComponent).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Compare with Original") {
                compareLines = viewModel.compareLines(for: match) ?? []
                compareTarget = match
            }
            Button("Keep This One") { viewModel.keepConflictedCopy(match) }
            Button("Delete", role: .destructive) { viewModel.deleteConflictedCopy(match) }
        }
        .padding(8)
    }
}
