import SwiftUI

/// In-app documentation, opened from the Help menu (⌘?) as its own `Window` scene —
/// a topic sidebar plus a scrollable detail pane, styled with the same Nocturne tokens
/// as the rest of the app rather than a native Help Book/AppKit help viewer.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting Started"
    case versionControl = "Version Control & Sync"
    case compileExport = "Compile & Export"
    case shortcuts = "Keyboard Shortcuts"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .versionControl: "arrow.triangle.branch"
        case .compileExport: "square.and.arrow.up"
        case .shortcuts: "keyboard"
        }
    }
}

struct HelpView: View {
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: topic.systemImage)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.text)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.surface)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            ScrollView {
                content(for: selection ?? .gettingStarted)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Color.bg)
        }
        .tint(Theme.Color.accent)
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted: GettingStartedHelp()
        case .versionControl: VersionControlHelp()
        case .compileExport: CompileExportHelp()
        case .shortcuts: ShortcutsHelp()
        }
    }
}

// MARK: - Shared building blocks

private struct HelpH1: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.Font.heading(24))
            .foregroundStyle(Theme.Color.text)
            .padding(.bottom, 6)
    }
}

private struct HelpH2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.Font.heading(15))
            .foregroundStyle(Theme.Color.accent200)
            .padding(.top, 18)
    }
}

private struct HelpBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(Theme.Font.body(13))
            .foregroundStyle(Theme.Color.text.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }
}

private struct HelpBullets: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Theme.Color.textMuted)
                    Text(LocalizedStringKey(item))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text.opacity(0.9))
                .lineSpacing(3)
            }
        }
    }
}

private struct HelpShortcutRow: View {
    let action: String
    let keys: String
    var body: some View {
        HStack {
            Text(action)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            NocturneTag(text: keys, style: .neutral)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Getting Started

private struct GettingStartedHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HelpH1("Getting Started")
            HelpBody("Drafter organizes a manuscript as chapters and scenes in a **binder** on the left, with a distraction-free editor on the right.")

            HelpH2("Creating and opening projects")
            HelpBullets([
                "**New Project…** (⌥⇧⌘N) asks for a title, author, save location, a manuscript type, and a version control mode. Manuscript type only sets the default chapter heading format (\"Chapter 1\" vs. bare \"1\") — you can change it later from the Compile sheet.",
                "**Open Project…** (⌘O) opens a project already on disk.",
                "**Add Existing Project…** (⇧⌘O) clones a project from GitHub, including picking one straight from your connected account's repositories.",
            ])

            HelpH2("The binder")
            HelpBullets([
                "**New Scene…** (⌘N), **New Chapter…** (⇧⌘N), and **New Note…** (⌥⌘N) add to the binder. Drag scenes between chapters, or into Front Matter / Back Matter / Notes, to reorder.",
                "**Delete** (⌘⌫) moves the selected chapter, scene, or note to the Trash rather than deleting it outright.",
            ])

            HelpH2("Writing")
            HelpBullets([
                "**Toggle Typewriter Scrolling** (⌥⌘T) keeps your cursor pinned at a fixed vertical position as you type, instead of scrolling the page underneath it.",
                "**Toggle Inspector** (⌥⌘I) shows or hides the right-hand panel, which holds your word-count Targets and the History panel for the open scene.",
                "Edits autosave to disk continuously — there's no separate \"save the file\" step.",
            ])

            HelpH2("Targets")
            HelpBody("The Targets panel tracks total project words against the goal set in **Project Settings… → Goals** (⇧⌘,), plus how many words you've added this session and a per-chapter breakdown.")

            HelpH2("Find & Replace")
            HelpBody("**Find & Replace in Project…** (⇧⌘F) searches every scene at once, not just the one you have open. Results are grouped by scene — click one to jump straight to that match, or replace matches individually or all at once without leaving the sheet.")
        }
    }
}

// MARK: - Version Control & Sync

private struct VersionControlHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HelpH1("Version Control & Sync")
            HelpBody("Every project uses one of two version control modes, chosen when it's created and visible afterward in **Project Settings… → Version Control**.")

            HelpH2("Git + GitHub")
            HelpBullets([
                "A private git repository with automatic merging and structured conflict resolution.",
                "Connect an account under **Settings → Version Control** by pasting a GitHub personal access token and clicking **Test Connection**. Once connected, **Add Existing Project…** can list that account's own Drafter repositories to clone.",
            ])

            HelpH2("Local Files + Cloud Folder")
            HelpBullets([
                "Whole-project snapshots are saved to a **History** folder next to your manuscript — no GitHub account needed.",
                "To sync across machines, put the project folder inside iCloud Drive, Dropbox, Google Drive, OneDrive, or Box; Drafter detects and reports which one it sees. Without a synced folder, snapshots still work, just on one machine.",
                "**Snapshot Now** and **Open History in Finder** are available in both **Settings → Version Control** and **Project Settings… → Version Control**.",
            ])

            HelpH2("Autosave and checkpoints")
            HelpBullets([
                "Edits write to disk continuously; separately, about 90 seconds after your last edit (**Settings → Versioning → Autocommit Debounce**) Drafter bundles everything since the last commit into a single commit or snapshot, rather than one per keystroke.",
                "Losing window focus, closing the project, exporting, and **Save Project** (⌘S) all force an immediate commit regardless of the debounce.",
            ])

            HelpH2("Sync (Git mode)")
            HelpBody("Drafter fetches from GitHub when a project opens, on a periodic timer (**Settings → Versioning → Sync Fetch Interval**), whenever the window regains focus, about 30 seconds after any commit, and once more right before the project closes.")

            HelpH2("History")
            HelpBody("The History panel (right-hand Inspector) lists every commit or snapshot touching the currently open scene, with relative time, machine name, and word-count delta. Click an entry to see a two-pane diff against your current text. Right-click → **Restore as Copy** brings that older version back as a new scene alongside the current one, rather than overwriting it.")

            HelpH2("Resolving conflicts")
            HelpBullets([
                "**Git mode:** if the same scene changed on two machines, a conflict sheet lists each affected file with **Compare**, **Keep Mine**, **Keep Theirs**, and **Keep Both** (which appends both versions so nothing is lost). **Done** commits and pushes once every file is resolved.",
                "**Local-file mode:** there's no merge engine, so instead a banner appears when your cloud-sync client leaves behind a conflicted-copy file — **Compare with Original**, **Keep This One**, or **Delete**. It never blocks you from continuing to write.",
                "In either mode, opening a project or regaining focus checks for activity from another machine in roughly the last five minutes and shows a heads-up if it finds any, so you notice before overwriting recent work.",
            ])
        }
    }
}

// MARK: - Compile & Export

private struct CompileExportHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HelpH1("Compile & Export")
            HelpBody("**Compile…** (⇧⌘E) turns the binder into a finished document in one of three formats. Every format shares an output location, a chapter title format (e.g. \"Chapter {n}\" vs. \"{n}\"), a scene separator, and a live word-count estimate shown below the settings.")

            HelpH2("EPUB")
            HelpBody("Choose a **Template** — Novel or Short Story — which swaps the stylesheet. A short story compiles as one continuous flow with numbered scene breaks instead of per-chapter pages and headings.")

            HelpH2("Print PDF")
            HelpBody("Set trim size, body font, point size, first-line indent, and heading font. Compiled with the bundled **typst**; the page count shown before compiling is a rough estimate — the real count comes from the compile itself.")

            HelpH2("Standard Manuscript Format (DOCX)")
            HelpBody("Just a manuscript font choice (Times New Roman or Courier New) — this format targets submission, not a styled book layout, so front/back matter and the other formatting options don't apply.")

            HelpH2("Front & back matter")
            HelpBullets([
                "Six standard sections live as ordinary scenes in the binder: **Title Page**, **Copyright**, and **Dedication** under Front Matter; **Review Ask**, **Newsletter**, and **About the Author** under Back Matter.",
                "**Generate Front/Back Matter** (binder toolbar) fills in whichever of the six don't exist yet from a template — it never overwrites ones you've already written.",
                "Drop an image file onto the Front Matter section to set it as the book's cover.",
                "EPUB and Print PDF each have their own **Include Front Matter** / **Include Back Matter** toggles in the Compile sheet; DOCX always omits both.",
            ])

            HelpH2("Required tools")
            HelpBody("Compiling needs **pandoc** (all formats) and **typst** (Print PDF only). Drafter bundles both for Apple Silicon; on Intel Macs, or if the bundled copies won't run, it falls back to Homebrew or PATH installs. If auto-detection picks the wrong binary, point it at a specific one under **Settings → Tools**.")
        }
    }
}

// MARK: - Keyboard Shortcuts

private struct ShortcutsHelp: View {
    private struct Group {
        let title: String
        let rows: [(String, String)]
    }

    private let groups: [Group] = [
        Group(title: "Project", rows: [
            ("New Project…", "⌥⇧⌘N"),
            ("Add Existing Project…", "⇧⌘O"),
            ("Open Project…", "⌘O"),
            ("Save Project", "⌘S"),
            ("Compile…", "⇧⌘E"),
            ("Project Settings…", "⇧⌘,"),
        ]),
        Group(title: "Find", rows: [
            ("Find & Replace in Project…", "⇧⌘F"),
        ]),
        Group(title: "Format", rows: [
            ("Italic", "⌘I"),
            ("Bold", "⌘B"),
        ]),
        Group(title: "Binder", rows: [
            ("New Scene…", "⌘N"),
            ("New Chapter…", "⇧⌘N"),
            ("New Note…", "⌥⌘N"),
            ("Delete", "⌘⌫"),
            ("Toggle Inspector", "⌥⌘I"),
            ("Toggle Typewriter Scrolling", "⌥⌘T"),
        ]),
        Group(title: "Help", rows: [
            ("Drafter Help", "⌘?"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HelpH1("Keyboard Shortcuts")
            ForEach(groups, id: \.title) { group in
                HelpH2(group.title)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.rows, id: \.0) { row in
                        HelpShortcutRow(action: row.0, keys: row.1)
                        if row.0 != group.rows.last?.0 {
                            Rectangle().fill(Theme.Color.divider).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
