import AppKit
import ProjectStore
import SnapshotService
import SwiftUI

/// Editor for `project.json` (§4.5, §10). Works on a local draft; nothing is written
/// until Save, matching `project.json`'s description as "rarely written" — no
/// autosave-on-every-keystroke here the way scene text gets.
///
/// Three tabs: Metadata (Book/Series/Publishing combined — compile/print formatting
/// settings were dropped entirely, since the Compile sheet already edits those at
/// export time, so duplicating them here was redundant), Goals, and Version Control
/// (which used to be its own standalone toolbar sheet).
struct ProjectMetadataEditor: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case metadata = "Metadata", goals = "Goals", versionControl = "Version Control"
        var id: String { rawValue }
    }

    @State private var draft: ProjectMetadata
    @State private var selectedTab: Tab = .metadata
    let snapshotService: SnapshotService?
    let workingTree: URL?
    let isGitHubConnected: Bool
    let onConnectToGitHub: () -> Void
    let onSnapshotNow: () async -> Void
    let onSave: (ProjectMetadata) -> Void
    let onCancel: () -> Void

    init(
        metadata: ProjectMetadata,
        snapshotService: SnapshotService?,
        workingTree: URL?,
        isGitHubConnected: Bool,
        onConnectToGitHub: @escaping () -> Void,
        onSnapshotNow: @escaping () async -> Void,
        onSave: @escaping (ProjectMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: metadata)
        self.snapshotService = snapshotService
        self.workingTree = workingTree
        self.isGitHubConnected = isGitHubConnected
        self.onConnectToGitHub = onConnectToGitHub
        self.onSnapshotNow = onSnapshotNow
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabRow
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tabContent
                }
                .padding(18)
            }
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.nocturneSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .buttonStyle(.nocturnePrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .background(Theme.Color.surface)
    }

    private var header: some View {
        HStack {
            Text("Project Settings")
                .font(Theme.Font.heading(17))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.nocturneIcon)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(Theme.Font.body(13))
                        .foregroundStyle(selectedTab == tab ? Theme.Color.accent : Theme.Color.textMuted)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selectedTab == tab ? Theme.Color.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .metadata: metadataFields
        case .goals: goalsFields
        case .versionControl: versionControlContent
        }
    }

    private var metadataFields: some View {
        Group {
            sectionLabel("Book", isFirst: true)
            NocturneField(label: "Title", text: $draft.title)
            NocturneField(label: "Subtitle", text: $draft.subtitle)
            NocturneField(label: "Author", text: $draft.author)
            NocturneField(label: "Description", text: $draft.description, multilineRange: 3...6)

            sectionLabel("Series")
            NocturneField(label: "Series Name", text: $draft.series.name)
            NocturneField(label: "Number in Series", text: seriesNumberText)

            sectionLabel("Publishing")
            Stepper("Copyright Year: \(String(draft.copyrightYear))", value: $draft.copyrightYear, in: 1900...2100)
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.Color.text)
                .tint(Theme.Color.accent)
            NocturneField(label: "Publisher", text: $draft.publisher)
            NocturneField(label: "ISBN", text: $draft.isbn)
            NocturneField(label: "Language", text: $draft.language)

            sectionLabel("Manuscript")
            NocturneField(label: "Address", text: $draft.manuscript.address)
            NocturneField(label: "Phone", text: $draft.manuscript.phone)
            NocturneField(label: "Email", text: $draft.manuscript.email)
            NocturneField(label: "Agent Name", text: $draft.manuscript.agentName)
            NocturneField(label: "Agent Address", text: $draft.manuscript.agentAddress)
            NocturneDropdown(label: "Manuscript Font", selection: $draft.manuscript.bodyFont, options: ["Times New Roman", "Courier New"]) { $0 }
        }
    }

    private var goalsFields: some View {
        NocturneField(label: "Word Count Goal", text: targetWordsText)
    }

    /// A visible divider above every section but the first, plus more top breathing
    /// room than a plain muted label alone gave — that made "Goals" read as just
    /// another line of text above the word-count field rather than its own section.
    private func sectionLabel(_ text: String, isFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isFirst {
                Rectangle().fill(Theme.Color.divider).frame(height: 1)
            }
            Text(text.uppercased())
                .font(Theme.Font.heading(11))
                .tracking(0.6)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.top, isFirst ? 0 : 10)
    }

    @ViewBuilder
    private var versionControlContent: some View {
        if draft.versionControl == .localFile, let snapshotService, let workingTree {
            LocalFileVersionControlTabContent(
                snapshotService: snapshotService,
                workingTree: workingTree,
                onSnapshotNow: onSnapshotNow
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                kvRow("Mode", "Git + GitHub")
                kvRow("GitHub Account", isGitHubConnected ? "Connected" : "Not connected")
                if !isGitHubConnected {
                    Button("Connect to GitHub…", action: onConnectToGitHub)
                        .buttonStyle(.nocturneSecondary)
                }
                Text("Manage the GitHub personal access token itself in Drafter's Settings.")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textMuted)
            }
        }
    }

    private func kvRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            Text(value)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
        }
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

/// §12's Local-file-mode version control info, embedded as Project Settings' Version
/// Control tab rather than its own standalone sheet.
private struct LocalFileVersionControlTabContent: View {
    @State private var viewModel: LocalFileVersionControlViewModel
    let onSnapshotNow: () async -> Void

    init(snapshotService: SnapshotService, workingTree: URL, onSnapshotNow: @escaping () async -> Void) {
        _viewModel = State(initialValue: LocalFileVersionControlViewModel(snapshotService: snapshotService, workingTree: workingTree))
        self.onSnapshotNow = onSnapshotNow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                kvRow("Mode", "Local Files + Cloud Folder")
                kvRow("Sync", viewModel.providerText)
                kvRow("Last Snapshot", viewModel.lastSnapshotText)
                kvRow("Snapshots Kept", "\(viewModel.snapshotCount)")
                kvRow("History Size", viewModel.historySizeText)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Button("Open History in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([viewModel.historyFolderURL])
                }
                .buttonStyle(.nocturneSecondary)
                Button("Snapshot Now") {
                    Task {
                        await onSnapshotNow()
                        await viewModel.load()
                    }
                }
                .buttonStyle(.nocturneSecondary)
                .disabled(viewModel.isLoading)
            }
        }
        .task { await viewModel.load() }
    }

    private func kvRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            Text(value)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
        }
    }
}
