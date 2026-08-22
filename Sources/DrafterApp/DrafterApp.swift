import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the "Save Project" (§8.5's checkpoint-commit) menu command;
    /// `ContentView` observes it since the scene/project state it needs to act on lives
    /// there, not at the App level.
    static let drafterRequestCheckpoint = Notification.Name("DrafterRequestCheckpoint")

    /// Posted by `SettingsViewModel` after successfully saving a verified token
    /// (§5.3) — Settings is a separate `Scene`/window from `ContentView`, so this is
    /// how the open project's `SyncScheduler` finds out it should retry immediately
    /// (§12.2 point 4) rather than waiting out the next periodic tick.
    static let drafterCredentialsUpdated = Notification.Name("DrafterCredentialsUpdated")

    // The File menu's New/Open commands — moved out of the in-content toolbar so the
    // toolbar only holds actions specific to the currently open project.
    static let drafterRequestNewProject = Notification.Name("DrafterRequestNewProject")
    static let drafterRequestAddExistingProject = Notification.Name("DrafterRequestAddExistingProject")
    static let drafterRequestOpenProject = Notification.Name("DrafterRequestOpenProject")

    // Keyboard-shortcut-only menu commands for existing toolbar/context-menu actions
    // that previously had no shortcut at all — same "post a notification, ContentView
    // acts on it" pattern as the File menu commands above, since the state they touch
    // (sheets, selection, the binder tree) all lives in `ContentView`, not here.
    static let drafterRequestCompile = Notification.Name("DrafterRequestCompile")
    static let drafterRequestProjectSettings = Notification.Name("DrafterRequestProjectSettings")
    static let drafterRequestNewChapter = Notification.Name("DrafterRequestNewChapter")
    static let drafterRequestNewScene = Notification.Name("DrafterRequestNewScene")
    static let drafterRequestNewNote = Notification.Name("DrafterRequestNewNote")
    static let drafterRequestDeleteSelection = Notification.Name("DrafterRequestDeleteSelection")
    static let drafterRequestToggleInspector = Notification.Name("DrafterRequestToggleInspector")
    static let drafterRequestToggleTypewriterScrolling = Notification.Name("DrafterRequestToggleTypewriterScrolling")

    /// §8.3 point 8's ⇧⌘F — project-wide find & replace.
    static let drafterRequestProjectFindReplace = Notification.Name("DrafterRequestProjectFindReplace")
}

@main
struct DrafterApp: App {
    @Environment(\.openWindow) private var openWindow

    init() {
        // `swift run` launches a bare executable, not a real .app bundle, so without
        // this the window never properly becomes key — clicks land, but keyboard
        // input (typing, shortcuts) silently goes nowhere. Real app bundles (Xcode
        // builds, or a packaged release) get this for free from LSUIElement/Info.plist
        // defaults; this makes `swift run` behave the same way during development.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                // New Project/Add Existing are one-time-per-project setup actions, not
                // everyday commands, so they get the heavier combos — the plain ⌘N/⇧⌘N
                // slots go to New Scene/New Chapter (Binder menu below), which are used
                // constantly while writing.
                Button("New Project…") {
                    NotificationCenter.default.post(name: .drafterRequestNewProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])

                Button("Add Existing Project…") {
                    NotificationCenter.default.post(name: .drafterRequestAddExistingProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open Project…") {
                    NotificationCenter.default.post(name: .drafterRequestOpenProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                // §8.5: ⌘S is "Save Project" (checkpoint-commit now), not a file save in
                // the traditional sense — there is no separate save button (§8.3 point
                // 9's autosave already covers that); this just forces an immediate one.
                Button("Save Project") {
                    NotificationCenter.default.post(name: .drafterRequestCheckpoint, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            // Appends after the File menu's New/Open group (above) rather than
            // replacing anything — these were previously toolbar-only actions with no
            // shortcut at all.
            CommandGroup(after: .newItem) {
                Button("Compile…") {
                    NotificationCenter.default.post(name: .drafterRequestCompile, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Project Settings…") {
                    NotificationCenter.default.post(name: .drafterRequestProjectSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
            CommandMenu("Find") {
                Button("Find & Replace in Project…") {
                    NotificationCenter.default.post(name: .drafterRequestProjectFindReplace, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Format") {
                Button("Italic") {
                    NSApp.sendAction(#selector(TypewriterTextView.drafterToggleItalic(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Bold") {
                    NSApp.sendAction(#selector(TypewriterTextView.drafterToggleBold(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            // The binder's create/delete actions (§8.2) and the two editor toolbar
            // toggles — all previously reachable only by clicking, never a shortcut.
            CommandMenu("Binder") {
                // New Scene is the single most-used create action while writing, so it
                // gets the plain ⌘N slot; New Chapter (second most common) gets ⇧⌘N.
                // New Note is rarer, so it takes the remaining ⌥⌘N slot.
                Button("New Scene…") {
                    NotificationCenter.default.post(name: .drafterRequestNewScene, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Chapter…") {
                    NotificationCenter.default.post(name: .drafterRequestNewChapter, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Note…") {
                    NotificationCenter.default.post(name: .drafterRequestNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                // §8.2's "Delete" — moves the selected binder item to the Trash (same
                // confirmation dialog as the context menu's Delete, not an immediate
                // unconfirmed delete).
                Button("Delete") {
                    NotificationCenter.default.post(name: .drafterRequestDeleteSelection, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .drafterRequestToggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Toggle Typewriter Scrolling") {
                    NotificationCenter.default.post(name: .drafterRequestToggleTypewriterScrolling, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
            // Replaces the default "Drafter Help" item (which would otherwise open a
            // nonexistent Help Book) with the in-app Help window below.
            CommandGroup(replacing: .help) {
                Button("Drafter Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }

        Window("Drafter Help", id: "help") {
            HelpView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 820, height: 580)
    }
}
