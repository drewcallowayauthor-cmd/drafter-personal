import ProjectStore
import SwiftUI

/// §8.3 point 8's project-wide find & replace sheet (⇧⌘F): a query/replacement pair,
/// case-sensitive/whole-word toggles, and a results list grouped by scene. Clicking a
/// result jumps the editor to that scene and offset and dismisses the sheet (§8.3: "a
/// results list that jumps to scene and offset"); "Replace"/"Replace All" work in place
/// without needing to jump anywhere first.
private struct SceneMatchGroup {
    let sceneURL: URL
    let sceneDisplayName: String
    var matches: [ProjectSearchMatch]
}

struct ProjectFindReplaceSheet: View {
    @State private var viewModel: ProjectFindReplaceViewModel
    @FocusState private var isQueryFocused: Bool
    let onCancel: () -> Void
    let onJump: (ProjectSearchMatch) -> Void

    init(
        performSearch: @escaping (ProjectSearchOptions) async -> [ProjectSearchMatch],
        performReplace: @escaping ([ProjectSearchMatch], String) async -> Set<URL>,
        flushOpenScene: @escaping () -> Void,
        reloadIfOpen: @escaping (Set<URL>) -> Void,
        onCancel: @escaping () -> Void,
        onJump: @escaping (ProjectSearchMatch) -> Void
    ) {
        _viewModel = State(
            initialValue: ProjectFindReplaceViewModel(
                performSearch: performSearch,
                performReplace: performReplace,
                flushOpenScene: flushOpenScene,
                reloadIfOpen: reloadIfOpen
            )
        )
        self.onCancel = onCancel
        self.onJump = onJump
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            fields
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            resultsList
            Rectangle().fill(Theme.Color.divider).frame(height: 1)
            footer
        }
        .frame(width: 520, height: 560)
        .background(Theme.Color.surface)
        .onAppear { isQueryFocused = true }
    }

    private var header: some View {
        HStack {
            Text("Find & Replace in Project")
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

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            NocturneField(label: "Find", text: $viewModel.query, externalFocus: $isQueryFocused)
            NocturneField(label: "Replace With", text: $viewModel.replacement)
            HStack(spacing: 16) {
                Toggle("Case Sensitive", isOn: $viewModel.caseSensitive)
                Toggle("Whole Word", isOn: $viewModel.matchWholeWord)
            }
            .tint(Theme.Color.accent)
            .foregroundStyle(Theme.Color.text)
            .font(Theme.Font.body(13))
        }
        .padding(18)
    }

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.query.isEmpty {
            emptyState(systemImage: "magnifyingglass", text: "Type a search term to find it across the whole project.")
        } else if viewModel.isSearching && viewModel.matches.isEmpty {
            emptyState(systemImage: "hourglass", text: "Searching…")
        } else if viewModel.matches.isEmpty {
            emptyState(systemImage: "checkmark", text: "No matches.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedMatches, id: \.sceneURL) { group in
                        sceneGroup(group)
                    }
                }
            }
        }
    }

    private func emptyState(systemImage: String, text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(Theme.Color.textMuted)
            Text(text)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var groupedMatches: [SceneMatchGroup] {
        var groups: [SceneMatchGroup] = []
        for match in viewModel.matches {
            if groups.indices.last.map({ groups[$0].sceneURL }) == match.sceneURL {
                groups[groups.count - 1].matches.append(match)
            } else {
                groups.append(SceneMatchGroup(
                    sceneURL: match.sceneURL, sceneDisplayName: match.sceneDisplayName, matches: [match]
                ))
            }
        }
        return groups
    }

    private func sceneGroup(_ group: SceneMatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(group.sceneDisplayName) — \(group.matches.count) match\(group.matches.count == 1 ? "" : "es")")
                .font(Theme.Font.heading(12))
                .foregroundStyle(Theme.Color.textMuted)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(group.matches) { match in
                resultRow(match)
            }
        }
    }

    private func resultRow(_ match: ProjectSearchMatch) -> some View {
        HStack(spacing: 8) {
            Button {
                onJump(match)
            } label: {
                highlightedSnippet(match)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Replace") { Task { await viewModel.replace(match) } }
                .buttonStyle(.nocturneGhost)
                .font(Theme.Font.body(11))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func highlightedSnippet(_ match: ProjectSearchMatch) -> Text {
        guard let range = Range(match.snippetMatchRange, in: match.snippet) else {
            return Text(match.snippet)
        }
        let prefix = String(match.snippet[..<range.lowerBound])
        let highlighted = String(match.snippet[range])
        let suffix = String(match.snippet[range.upperBound...])
        return Text(prefix) + Text(highlighted).foregroundStyle(Theme.Color.accent).bold() + Text(suffix)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if viewModel.isReplacing {
                ProgressView().controlSize(.small)
            }
            Text(
                viewModel.matches.isEmpty
                    ? ""
                    : "\(viewModel.matches.count) match\(viewModel.matches.count == 1 ? "" : "es")"
            )
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            Button("Close") { onCancel() }
                .buttonStyle(.nocturneSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Replace All") { Task { await viewModel.replaceAll() } }
                .buttonStyle(.nocturnePrimary)
                .disabled(viewModel.matches.isEmpty || viewModel.isReplacing)
        }
        .padding(16)
    }
}
