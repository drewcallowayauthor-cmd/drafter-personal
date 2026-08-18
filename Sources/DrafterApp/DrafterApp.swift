import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the Checkpoint menu command; `ContentView` observes it since the
    /// scene/project state it needs to act on lives there, not at the App level.
    static let drafterRequestCheckpoint = Notification.Name("DrafterRequestCheckpoint")
}

@main
struct DrafterApp: App {
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
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                // §8.5: ⌘S is "Checkpoint (commit now)", not a file save — there is no
                // save button (§8.3 point 9's autosave already covers that).
                Button("Checkpoint") {
                    NotificationCenter.default.post(name: .drafterRequestCheckpoint, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
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
        }
    }
}
