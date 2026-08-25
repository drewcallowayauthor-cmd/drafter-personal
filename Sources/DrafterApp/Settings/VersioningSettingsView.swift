import SwiftUI

/// §12's Versioning pane: autosave/autocommit timing (both modes) plus history size and
/// "Run Maintenance" for whichever project is currently open, via `OpenProjectHandle`
/// (Settings is a separate `Scene` with no direct reference to `ContentView`'s project).
struct VersioningSettingsView: View {
    @Bindable var prefs = AppPreferences.shared
    @State private var handle = OpenProjectHandle.shared
    @State private var historySize: String?
    @State private var isRunningMaintenance = false
    @State private var maintenanceMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            steppedRow(label: "Autosave Interval", value: $prefs.autosaveDelaySeconds, range: 1...10, suffix: "s")
            steppedRow(
                label: "Autocommit Debounce", value: $prefs.autocommitDebounceSeconds,
                range: 15...300, step: 15, suffix: "s"
            )
            steppedRow(
                label: "Sync Fetch Interval", value: $prefs.syncFetchIntervalSeconds,
                range: 30...600, step: 30, suffix: "s"
            )

            Rectangle().fill(Theme.Color.divider).frame(height: 1)

            if handle.workingTreeRoot == nil {
                Text("No project open.")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.textMuted)
            } else {
                HStack {
                    Text("History Size")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    Text(historySize ?? "—")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                Button("Run Maintenance") { Task { await runMaintenance() } }
                    .buttonStyle(.nocturneSecondary)
                    .disabled(isRunningMaintenance)
                if let maintenanceMessage {
                    Text(maintenanceMessage)
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.textMuted)
                }
            }
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(Theme.Color.surface)
        .task(id: handle.workingTreeRoot) { await loadHistorySize() }
    }

    private func loadHistorySize() async {
        historySize = try? await handle.historySizeDescription()
    }

    private func runMaintenance() async {
        isRunningMaintenance = true
        maintenanceMessage = nil
        defer { isRunningMaintenance = false }
        do {
            try await handle.runMaintenance()
            await loadHistorySize()
            maintenanceMessage = "Done."
        } catch {
            maintenanceMessage = "Couldn't run maintenance — \(error.localizedDescription)"
        }
    }

    private func steppedRow(
        label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String
    ) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Text("\(Int(value.wrappedValue)) \(suffix)")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.textMuted)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }
}
