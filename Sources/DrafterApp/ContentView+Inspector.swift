import SwiftUI

extension ContentView {
    @ViewBuilder
    var inspector: some View {
        if projectViewModel.metadata != nil {
            VStack(spacing: 0) {
                TargetsPanel(
                    totals: targetsViewModel.totals,
                    targetWords: projectViewModel.metadata?.target.words ?? 0,
                    sessionWords: targetsViewModel.sessionWords
                )
                Rectangle().fill(Theme.Color.divider).frame(height: 1)
                historySection
            }
            .background(Theme.Color.surface)
        } else {
            ContentUnavailableView(
                "No Project Open",
                systemImage: "chart.bar",
                description: Text("Open a project to see word count targets and history.")
            )
        }
    }

    @ViewBuilder
    var historySection: some View {
        if let historyViewModel, let sceneURL = selectedSceneURL, isOpenableScene(sceneURL),
            let workingTree = projectViewModel.workingTreeRoot {
            HistoryPanel(
                history: historyViewModel,
                sceneURL: sceneURL,
                workingTree: workingTree,
                currentBody: sceneEditor.document?.body ?? ""
            )
        } else {
            ContentUnavailableView(
                "No Scene Selected",
                systemImage: "clock",
                description: Text("Select a scene to see its history.")
            )
        }
    }
}
