import CredentialStore
import SwiftUI

/// §5.9's "Add Existing Project" path: pick from the token account's own Drafter
/// repos rather than pasting a clone URL.
struct GitHubRepoPickerSheet: View {
    @State private var viewModel = GitHubRepoPickerViewModel()
    let onSelect: (GitHubRepository) -> Void
    let onCancel: () -> Void

    var body: some View {
        NocturneSheet(title: "Add Existing Project", width: 420, onClose: onCancel) {
            content
        } footer: {
            Button("Cancel", action: onCancel)
                .buttonStyle(.nocturneSecondary)
        }
        .frame(height: 420)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Couldn't Load Repositories",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if viewModel.repositories.isEmpty {
            ContentUnavailableView(
                "No Drafter Projects Found",
                systemImage: "folder",
                description: Text("None of this account's repositories look like Drafter projects.")
            )
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.repositories) { repository in
                    Button {
                        onSelect(repository)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repository.name)
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(Theme.Color.text)
                                Text(repository.fullName)
                                    .font(Theme.Font.body(11))
                                    .foregroundStyle(Theme.Color.neutral500)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RepoRowButtonStyle())
                    if repository.id != viewModel.repositories.last?.id {
                        Rectangle().fill(Theme.Color.divider).frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct RepoRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovering ? Theme.Color.text.opacity(0.06) : .clear)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}
