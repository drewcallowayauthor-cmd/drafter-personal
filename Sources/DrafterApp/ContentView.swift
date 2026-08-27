import AppKit
import DrafterCore
import GitService
import ProjectStore
import SwiftUI
import UniformTypeIdentifiers

/// The Binder/Editor/Inspector layout (§8.1). Inspector currently holds History (§5.8);
/// Scene and Targets sections are later additions to the same pane.
struct ContentView: View {
    @State var projectViewModel = ProjectViewModel()
    @State var sceneEditor = SceneEditorViewModel(
        autosaveDelay: .seconds(AppPreferences.shared.autosaveDelaySeconds)
    )
    @State var historyViewModel: HistoryViewModel?
    @State var conflictedCopyViewModel = ConflictedCopyViewModel()
    @State var targetsViewModel = TargetsViewModel()
    @State var isImporterPresented = false
    @State var isInspectorPresented = true
    @State var selectedSceneURL: URL?
    @State var appPreferences = AppPreferences.shared
    @State var regenerateConfirmation: (template: FrontBackMatterTemplate, displayName: String)?
    @State var frontBackMatterError: String?
    @State var isMetadataEditorPresented = false
    @State var isCompileSheetPresented = false
    @State var compiledResult: CompileOutcome?
    @State var isNewProjectSheetPresented = false
    @State var isOnboardingSheetPresented = !AppPreferences.shared.hasCompletedOnboarding
    @State var isCloneProjectSheetPresented = false
    @State var isConflictSheetPresented = false
    @State var isNewChapterSheetPresented = false
    /// Non-nil while the "New Scene…" prompt is up, naming which chapter it's for.
    @State var newSceneChapterURL: URL?
    /// Non-nil while the "New Note…" prompt is up.
    @State var isNewNoteSheetPresented = false
    /// Which Manuscript chapters' `DisclosureGroup`s are expanded — reset to "all
    /// expanded" whenever a project opens (§8.1: the binder should show its contents
    /// immediately, not require expanding every chapter by hand), then left to the
    /// user's own expand/collapse choices for the rest of the session. Held in a
    /// side store (never read in `body`) so a long chapter list doesn't trip the
    /// macOS `List` + `DisclosureGroup` overlap bug — see `BinderChapterExpansion`.
    @State var binderExpansion = BinderChapterExpansion()
    /// Non-nil while the binder's "Rename…" prompt is up.
    @State var renameTarget: BinderRenameTarget?
    /// Non-nil while the binder's delete confirmation is up.
    @State var deleteTarget: BinderDeleteTarget?
    /// §6.3's "open with unsaved edits" rule: set to the scene's URL when an external
    /// change (a git integration) touched the file the editor has dirty, so the inline
    /// bar shows only for that scene, not a stale one after switching away.
    @State var externalChangeConflictURL: URL?
    @State var isExternalChangeCompareSheetPresented = false
    @State var externalChangeDiffLines: [SceneDiffLine] = []
    @State var toastCenter = ToastCenter()
    @State var isProjectFindReplacePresented = false
    /// §8.3 point 8's "jumps to scene and offset" — set alongside `selectedSceneURL`
    /// when a find-in-project result is clicked; `pendingJumpSceneURL` guards against
    /// handing a stale range to whichever scene happens to be open once the selection
    /// change (and its dispatch-async'd `sceneEditor.open`, see `onChange` below) lands.
    @State var pendingJump: SceneTextJumpRequest?
    @State var pendingJumpSceneURL: URL?
    @Environment(\.scenePhase) var scenePhase

    // Split into several grouped chunks rather than one long modifier chain: a chain
    // this long makes the type checker choke ("unable to type-check this expression
    // in reasonable time") well before it's actually ambiguous — each `withX` below is
    // small enough to check on its own.
    var body: some View {
        withShortcutHandlers(withLifecycleHandlers(withProjectSheets(withAlerts(mainLayout))))
    }

    var mainLayout: some View {
        NavigationSplitView {
            binderList
        } detail: {
            VStack(spacing: 0) {
                editorToolbar
                if !conflictedCopyViewModel.matches.isEmpty {
                    ConflictedCopyBanner(viewModel: conflictedCopyViewModel)
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.bg)
            .nocturneToastOverlay(center: toastCenter)
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspector
        }
        .tint(Theme.Color.accent)
    }
}

/// Identifies which binder item the "Rename…" sheet is renaming.
struct BinderRenameTarget: Identifiable {
    let url: URL
    let currentTitle: String
    var id: URL { url }
}

/// Identifies which binder item the delete confirmation is about to remove.
struct BinderDeleteTarget: Identifiable {
    let url: URL
    let displayName: String
    let isChapter: Bool
    var id: URL { url }
}

#Preview {
    ContentView()
}

/// Pushes Settings' Versioning-pane intervals into the currently open project's live
/// schedulers as they change, instead of only taking effect the next time a project is
/// opened. Split out of `ContentView.body` because folding these four `onChange`
/// handlers directly into that already-huge modifier chain pushes the type checker
/// over its expression-complexity limit.
struct VersioningPreferencesSync: ViewModifier {
    let appPreferences: AppPreferences
    let sceneEditor: SceneEditorViewModel
    let projectViewModel: ProjectViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: appPreferences.autosaveDelaySeconds) { _, newValue in
                sceneEditor.autosaveDelay = .seconds(newValue)
            }
            .onChange(of: appPreferences.autocommitDebounceSeconds) { _, newValue in
                projectViewModel.autocommitScheduler?.debounceDelay = .seconds(newValue)
            }
            .onChange(of: appPreferences.syncFetchIntervalSeconds) { _, newValue in
                projectViewModel.syncScheduler?.fetchInterval = .seconds(newValue)
            }
            .onChange(of: appPreferences.syncPushDebounceSeconds) { _, newValue in
                projectViewModel.syncScheduler?.pushDebounceDelay = .seconds(newValue)
            }
    }
}
