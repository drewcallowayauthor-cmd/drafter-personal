import ProjectStore
import SwiftUI

/// The one-time first-run screen (§5): asks the writer to pick a default version-control
/// mode before they ever see the New Project sheet. Shown once, gated by
/// `AppPreferences.hasCompletedOnboarding` — it doesn't create a project itself, it only
/// seeds `lastPickedVersionControlMode`, which `NewProjectSheet` reads as its own default.
struct OnboardingSheet: View {
    @State private var versionControl: VersionControlMode = .git
    let onFinish: () -> Void

    var body: some View {
        NocturneSheet(title: "Welcome to Drafter", width: 460, onClose: finish) {
            Text("Choose how your projects will be versioned and synced by default. You can change this per project when you create it.")
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            VersionControlModePicker(selection: $versionControl)
        } footer: {
            Button("Get Started", action: finish)
                .buttonStyle(.nocturnePrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Both "Get Started" and the header's × commit the current selection — there's no
    /// meaningful "cancel" here, since leaving `hasCompletedOnboarding` false would just
    /// bring this screen back on every subsequent launch.
    private func finish() {
        AppPreferences.shared.lastPickedVersionControlMode = versionControl.rawValue
        AppPreferences.shared.hasCompletedOnboarding = true
        onFinish()
    }
}
