import SwiftUI

/// §12's Settings window: five panes in doc order, each a self-contained view under
/// `Settings/`. The Version Control pane carries what used to be this file's whole body
/// (GitHub Sync) plus mode-dependent rows for whichever project is currently open.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "text.cursor") }
            VersionControlSettingsView()
                .tabItem { Label("Version Control", systemImage: "arrow.triangle.branch") }
            VersioningSettingsView()
                .tabItem { Label("Versioning", systemImage: "clock.arrow.circlepath") }
            ToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
    }
}
