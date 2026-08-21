import SwiftUI

/// The "No project open" welcome screen (per the design handoff's empty/secondary
/// states): centered title/subtext, primary actions, and a Recent list below a
/// divider. Replaces the old bare "Drafter" placeholder text.
struct NoProjectWelcomeView: View {
    var onNewProject: () -> Void
    var onAddExisting: () -> Void
    var onOpenRecent: (URL) -> Void

    @State private var recents: [RecentProjects.Entry] = RecentProjects.load()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Drafter")
                    .font(Theme.Font.heading(28))
                    .foregroundStyle(Theme.Color.text)
                Text("Open a project to get started, or create a new one.")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.textMuted)
            }

            HStack(spacing: 10) {
                Button("Add Existing…", action: onAddExisting)
                    .buttonStyle(.nocturneSecondary)
                Button("New Project…", action: onNewProject)
                    .buttonStyle(.nocturnePrimary)
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(Theme.Color.divider).frame(height: 1)
                    Text("RECENT")
                        .font(Theme.Font.body(10))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Color.textMuted)
                    VStack(spacing: 0) {
                        ForEach(recents) { entry in
                            Button { onOpenRecent(entry.url) } label: {
                                HStack {
                                    Text(entry.title)
                                        .font(Theme.Font.body(13))
                                        .foregroundStyle(Theme.Color.text)
                                    Spacer()
                                    Text(entry.path)
                                        .font(Theme.Font.body(11))
                                        .foregroundStyle(Theme.Color.neutral500)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RecentRowButtonStyle())
                        }
                    }
                }
                .frame(width: 380)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .onAppear { recents = RecentProjects.load() }
    }
}

private struct RecentRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovering ? Theme.Color.text.opacity(0.06) : .clear)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}
