import DrafterCore
import GitService
import SwiftUI

/// §5.7's per-file conflict resolution sheet: one row per conflicted path with
/// Compare / Keep Mine / Keep Theirs / Keep Both, and a Done button that commits and
/// pushes once every row is resolved.
struct ConflictSheet: View {
    @State private var viewModel: ConflictViewModel
    @State private var compareTarget: ConflictViewModel.FileConflict?
    @State private var compareLines: [SceneDiffLine] = []
    let onResolved: () -> Void
    let onCancel: () -> Void

    init(
        paths: [String],
        gitService: GitService,
        workingTree: URL,
        machineName: String,
        onResolved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: ConflictViewModel(paths: paths, gitService: gitService, workingTree: workingTree, machineName: machineName)
        )
        self.onResolved = onResolved
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(viewModel.conflicts.count) scene\(viewModel.conflicts.count == 1 ? "" : "s") changed on both machines")
                .font(Theme.Font.heading(17))
                .foregroundStyle(Theme.Color.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Rectangle().fill(Theme.Color.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.conflicts) { conflict in
                        conflictRow(conflict)
                        if conflict.id != viewModel.conflicts.last?.id {
                            Rectangle().fill(Theme.Color.divider).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }

            Rectangle().fill(Theme.Color.divider).frame(height: 1)

            HStack(spacing: 8) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(12))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.nocturneSecondary)
                Button("Done") {
                    Task {
                        if await viewModel.finalize() { onResolved() }
                    }
                }
                .buttonStyle(.nocturnePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.allResolved || viewModel.isFinalizing)
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
        .background(Theme.Color.surface)
        .task { await viewModel.loadMetadata() }
        .sheet(item: $compareTarget) { _ in
            DiffView(lines: compareLines, oldLabel: "Mine", newLabel: "Theirs")
                .nocturneSheetPresentation()
        }
    }

    @ViewBuilder
    private func conflictRow(_ conflict: ConflictViewModel.FileConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Color.text)

            if let mine = conflict.mine {
                Text("Mine — \(Self.relativeTime(mine)) on \(mine.machineName.isEmpty ? "this machine" : mine.machineName)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }
            if let theirs = conflict.theirs {
                Text("Theirs — \(Self.relativeTime(theirs)) on \(theirs.machineName.isEmpty ? "another machine" : theirs.machineName)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            }

            if conflict.isResolved {
                Label("Resolved", systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.accent)
            } else {
                HStack(spacing: 8) {
                    Button("Compare") {
                        Task {
                            compareLines = await viewModel.diffLines(for: conflict)
                            compareTarget = conflict
                        }
                    }
                    .buttonStyle(.nocturneSecondary)
                    Spacer()
                    Button("Keep Mine") { Task { await viewModel.keepMine(conflict) } }
                        .buttonStyle(.nocturneSecondary)
                    Button("Keep Theirs") { Task { await viewModel.keepTheirs(conflict) } }
                        .buttonStyle(.nocturneSecondary)
                    Button("Keep Both") { Task { await viewModel.keepBoth(conflict) } }
                        .buttonStyle(.nocturnePrimary)
                }
            }
        }
        .padding(.vertical, 10)
        .opacity(conflict.isResolved ? 0.55 : 1)
    }

    private static func relativeTime(_ entry: CommitLogEntry) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: entry.date, relativeTo: .now)
    }
}
