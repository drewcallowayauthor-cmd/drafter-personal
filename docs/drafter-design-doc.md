
# Drafter — Design Document

*Version 3 — dual version-control modes: Git+GitHub or local-file snapshots*

A minimal macOS writing app: chapter/scene organization, distraction-light markdown editing, automatic version control, sync across machines via a private GitHub repository or a synced local folder, and one-click export to EPUB and print-ready PDF.

---

## 1. Purpose and scope

### 1.1 What this replaces

Scrivener, used narrowly: binder-style chapter/scene organization, plain prose editing, snapshot versioning as a safety net, and compile-to-EPUB / compile-to-print. Nothing else.

### 1.2 Goals

1. **Chapter/scene file structure** legible in Finder and durable if the app disappears.
2. **Fast, quiet markdown editing** with a minimal formatting surface.
3. **Automatic version control** — the writer never thinks about it, never loses work.
4. **Two version-control modes, chosen once at project creation.** Git mode syncs across machines via a private GitHub repo with automatic merging of non-conflicting edits and structured conflict resolution. Local-file mode keeps timestamped snapshots on disk next to the manuscript and relies on the writer's own cloud-sync client — Box, Google Drive, iCloud Drive, or OneDrive — to move files between machines; the app never talks to those services' APIs, it just writes normal files into a normal folder.
5. **Repeatable export** to EPUB (KDP/KU) and print-ready PDF (KDP paperback), including generated front and back matter.
6. **Readable, tool-free history in either mode** — a manuscript's past is recoverable from Finder alone (Local-file mode) or from any git client (Git mode), never solely from this app.

### 1.3 Explicit non-goals

Do not build: corkboard/index cards, split editor, research folder with embedded PDFs/images, inline annotations and comments, custom metadata fields, collections/saved searches, scriptwriting mode, collaboration or multi-author workflows, iOS app, Scrivener import.

If a feature is not in section 10 or 11, it is out of scope for v1.

### 1.4 Design constraints

- **macOS only.** Minimum macOS 14. Single user, personal-use app — no App Store distribution, no App Sandbox (the app shells out to `git`, `pandoc`, and `typst`, which sandboxing complicates for little benefit).
- **Git-mode working copies live on local disk, never inside a cloud-synced folder.** Sync happens through GitHub, never through a filesystem sync client — see section 6. **Local-file mode inverts this on purpose**: the working copy is *expected* to live inside a cloud-synced folder when the writer wants cross-machine sync. There is no `.git` directory for a sync client to corrupt, so the usual hazard doesn't apply — see section 7.
- **Plain files are the source of truth in both modes.** The app is a view onto a folder. In Git mode, that folder is also a git working tree, and the manuscript additionally lives on GitHub. In Local-file mode, the manuscript lives wherever the cloud provider replicates it — the app depends on none of those providers' APIs.

---

## 2. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| UI shell | SwiftUI (macOS 14+) | Fast to build, adequate for a three-pane app |
| Prose editor | `NSTextView` wrapped in `NSViewRepresentable` | SwiftUI's `TextEditor` degrades on long documents and gives poor control over cursor, selection, typewriter scrolling |
| Data model | Plain files on disk + in-memory model | **No Core Data, no SwiftData.** The filesystem is the database |
| Version control & sync | `git` invoked as a subprocess with a private GitHub repo (Git mode), **or** timestamped whole-tree snapshots on disk (Local-file mode) | Sections 6 and 7 |
| Credentials | macOS Keychain via `Security` framework | Section 6.3 (Git mode only) |
| Markdown → EPUB | `pandoc` | Mature EPUB3 writer with metadata, TOC, CSS support |
| Markdown → print PDF | `pandoc` → Typst → PDF | Typst is a single ~30 MB binary with excellent book layout; avoids a 5 GB MacTeX dependency |
| Fallback print path | `pandoc` → `.docx` with reference doc | Escape hatch for manual touch-up, and for sending to an editor |

### 2.1 Binary dependencies

Bundle `pandoc` and `typst` in `Drafter.app/Contents/Resources/bin/`. Resolve in order: bundled → user-configured path in Settings → `PATH` (`/opt/homebrew/bin`, `/usr/local/bin`). If unresolvable, disable export UI with a one-line remediation message rather than crashing.

Do **not** bundle `git` — macOS ships it via Command Line Tools. If `git --version` fails, prompt to run `xcode-select --install`. A Git-mode project operates in a degraded read/write-only mode with snapshot fallback (§8.1) until git is available; a Local-file-mode project is unaffected, since it never needed git.

---

## 3. Core concepts

- **Project** — one book. Either a git working tree with a private GitHub repo as its remote (**Git mode**), or a plain folder with a `History/` snapshot directory (**Local-file mode**). The mode is fixed at creation — see section 5.
- **Chapter** — a subfolder of `Manuscript/`.
- **Scene** — a `.md` file inside a chapter folder.
- **Commit** (Git mode) — an automatic, silent version checkpoint written by git.
- **Snapshot** (Local-file mode) — an automatic, silent whole-tree copy written to `History/`.
- **Sync** — Git mode: fetch, fast-forward or merge, and push, all app-managed and continuous. Local-file mode: whatever the writer's cloud-sync client already does; the app does not implement sync itself.
- **Compile** — the transformation of a project into an EPUB or PDF.

---

## 4. On-disk project format

### 4.1 Location

Default location `~/Documents/Drafter/Projects/<Book Name>/`, configurable per project, with different placement rules per mode:

**Git mode** must **not** live inside a cloud-synced folder. Refuse `~/Library/CloudStorage/`, `~/Dropbox`, `~/Google Drive`, `~/OneDrive`, or `~/Library/Mobile Documents/` at creation and on every open (§14.1). A `.git` directory inside a sync client will eventually corrupt.

**Local-file mode** may live anywhere. Placing it inside one of those same cloud folders is the *intended* way to get cross-machine sync — the app treats that placement as a feature, since there's no `.git` directory for the sync client to threaten. Placed on plain local disk instead, the project still gets full local snapshot history, just no cross-machine sync. The app detects which provider folder (if any) a Local-file project sits in and names it in the status control (§7.6).

### 4.2 Directory layout

Git mode:

```
The Last Shift/                   ← git working tree root
├── .git/                         ← normal, local, healthy
├── .gitignore
├── .gitattributes
├── project.json
├── Manuscript/
│   ├── 01 Arrival/
│   │   ├── 01 Triage.md
│   │   ├── 02 The Board.md
│   │   └── 03 Room Nine.md
│   ├── 02 The First Hour/
│   │   ├── 01 Handoff.md
│   │   └── 02 Code Blue.md
│   └── 03 Interlude.md           ← a file at Manuscript root = its own chapter
├── FrontMatter/
│   ├── 01 Also By.md
│   ├── 02 Title Page.md
│   ├── 03 Copyright.md
│   └── 04 Dedication.md
├── BackMatter/
│   ├── 01 About the Author.md
│   └── 02 Newsletter.md
├── Notes/                        ← versioned, never compiled
│   └── outline.md
└── Resources/
    └── cover.jpg
```

Plain folder, not a macOS package. Everything except build artifacts is committed.

**.gitignore** (Git mode only)

```
.DS_Store
Build/
*.tmp
```

**.gitattributes** (Git mode only)

```
* text=auto eol=lf
*.md text
*.json text
*.jpg binary
*.png binary
```

Normalizing to LF matters — it prevents whole-file diffs caused by line-ending drift between machines.

Local-file mode replaces `.git/` with `History/`, a folder of timestamped whole-project snapshots (§7.2). There's no `.gitignore`/`.gitattributes` — nothing needs normalizing for a merge tool, since diffing happens inside the app, not a git client:

```
The Last Shift/                   ← plain folder, optionally inside Box/Drive/iCloud/OneDrive
├── project.json
├── Manuscript/                   ← same layout as Git mode
├── FrontMatter/
├── BackMatter/
├── Notes/
├── Resources/
└── History/                      ← snapshots, §7.2 — excluded from compile, included in sync
    ├── 2026-08-17 09-14-02 Josiah-MacBook-Pro/
    └── 2026-08-18 14-32-05 Josiah-Mac-Studio/
```

Everything under a `History/` entry mirrors the top-level project structure at that point in time — a snapshot can be opened and read with nothing but Finder.

### 4.3 Ordering

**Numeric filename prefixes are the sole source of truth for order.** `01 `, `02 `, `03 ` … zero-padded to two digits (three if a chapter exceeds 99 scenes).

Rationale: a central `order` array in `project.json` would be rewritten by every reorder, making it the one file most likely to produce a conflict in Git mode or a same-instant overwrite in Local-file mode. Filename prefixes distribute ordering across the tree instead.

Consequences:
- Reordering in the binder = renaming files. Batch the renames, then re-sequence the containing folder so prefixes stay dense (`01, 02, 03`, never `01, 03, 07`).
- Display name = filename minus prefix and extension.
- Tolerate missing or duplicate prefixes (sort by prefix, then alphabetically) and offer a "Re-sequence chapter" repair command.
- **Git mode** — use `git mv` for renames so `git log --follow` keeps working.
- **Local-file mode** — an ordinary `FileManager` move. There's no `git mv` to consult, so the History panel matches a scene across a rename using the scene's internal `id` (§4.4) rather than its path.

### 4.4 Per-scene metadata: YAML front matter

Scene metadata lives inside the scene file, for the same anti-conflict reason.

```markdown
---
id: 9F2C7B10-...
synopsis: Sam takes over the board and finds Room Nine already occupied.
status: draft
compile: true
---

The board was wrong.
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `id` | string (UUID) | generated on creation | Stable internal identity, never shown in UI. Used by Local-file mode's History panel to track a scene across renames (Git mode uses `git log --follow` instead) |
| `synopsis` | string | `""` | One-line summary, shown in binder inspector |
| `status` | enum | `draft` | `outline` / `draft` / `revised` / `final` |
| `compile` | bool | `true` | Exclude from export when `false` |
| `notes` | string | `""` | Free-form scratch, never compiled |

The compiler strips front matter before concatenation. It never reaches the output.

### 4.5 project.json

Book-level settings only. Rarely written, so its conflict surface is small.

```json
{
  "schemaVersion": 2,
  "id": "F4C2A1E9-...",
  "title": "The Last Shift",
  "subtitle": "",
  "author": "Tim Fleet",
  "versionControl": "git",
  "series": { "name": "", "number": null },
  "copyrightYear": 2026,
  "publisher": "",
  "isbn": "",
  "language": "en-US",
  "description": "",
  "target": { "words": 45000 },
  "compile": {
    "chapterTitleFormat": "Chapter {n}",
    "sceneSeparator": "* * *",
    "includeFrontMatter": true,
    "includeBackMatter": true,
    "coverImage": "Resources/cover.jpg"
  },
  "print": {
    "trimSize": "5x8",
    "bodyFont": "Palatino",
    "bodyPointSize": 11.5,
    "leading": 1.46,
    "chapterOpensOn": "either"
  }
}
```

`id` is generated once and used as a local cache key. `versionControl` is `"git"` or `"localFile"`, set at creation and never changed afterward (§5). In Git mode, the GitHub remote URL is the project's real identity and is *not* stored here — it already lives in `.git/config`.

### 4.6 Markdown dialect

Deliberately tiny.

| Feature | Syntax | Notes |
|---|---|---|
| Italic | `*word*` | The only inline formatting used in prose |
| Bold | `**word**` | Rare; titles are handled by templates, not inline bold |
| Scene break | `* * *` on its own line | Rendered per export target |
| Header | `# Title` | Front/back matter only; chapter titles come from folder names |
| Em dash | `—` literal | No editor-side punctuation transformation |

Enable Pandoc smart quotes on export (`--from=markdown+smart`) so straight quotes become curly in output. Do not transform them in the editor.

### 4.7 One paragraph per line — a hard rule

**The editor must never hard-wrap.** Each paragraph is exactly one line in the file, however long; wrapping is visual only.

This is load-bearing for the whole design, in both modes. In Git mode, git diffs and merges line by line, so one-paragraph-per-line means it can cleanly merge edits to *different* paragraphs of the same scene, and only flags a conflict when both machines edited *the same paragraph*. In Local-file mode, the same property makes the word-level diff view (§7.4) legible instead of a wall of reflowed red/green. Hard-wrapped prose would defeat both.

Blank line between paragraphs, as markdown redrafters. No trailing whitespace — strip on save.

---

## 5. Choosing a version-control mode

Chosen once, in the New Project sheet, before the first commit or snapshot is written. Not changeable later without exporting and starting a fresh project — the two histories are not interchangeable.

| | Git mode | Local-file mode |
|---|---|---|
| Cross-machine sync | Private GitHub repo, app-managed | Whatever cloud client the writer already runs (Box, Google Drive, iCloud Drive, OneDrive) — the app does not manage sync |
| Version history | Full git history, unified across machines | Timestamped whole-project snapshots in `History/` |
| Concurrent edits to different paragraphs | Merged automatically | Whichever snapshot syncs first wins locally; the cloud client's own conflicted-copy file, if it writes one, surfaces both versions |
| Concurrent edits to the same paragraph | Conflict sheet, per-file, three resolutions | Surfaced as a conflicted-copy banner (§7.5); no merge UI |
| Setup | GitHub account, a token or existing git credentials | None — pick a folder, optionally one already inside a cloud-sync client |
| Best for | Writers who want git's guarantees and don't mind a GitHub account | Writers who already trust Box/Drive/iCloud/OneDrive and want zero extra accounts |

New Project sheet copy:

> **How should this book be backed up and kept in sync?**
> ○ **Git + GitHub** — private repo, automatic merging, structured conflict resolution. Needs a GitHub account.
> ○ **Local files + your cloud folder** — snapshots stored next to your manuscript. Put the project in Box, Google Drive, iCloud Drive, or OneDrive to sync across machines — works without one too, just without sync.

Default to whichever mode the writer picked for their last project; on first launch, default to Git mode.

Both modes share the same binder, editor, History panel, and compile pipeline — see §9.1 for how the UI stays mode-agnostic.

---

## 6. Git mode: version control and sync

### 6.1 Model

One private GitHub repository per book. The local folder is an ordinary git working tree with `origin` pointing at that repo. There is nothing unusual about the setup — the app is a well-behaved git client with an opinionated automation layer on top.

Because the working copy is on local disk, all the pathologies of running git inside a sync client disappear: no placeholder files, no half-synced directories, no conflict copies inside `.git`.

History is unified across machines. There is one timeline.

### 6.2 Repository creation

On new project:

1. Slugify the title → `the-last-shift`. Let the user edit the repo name.
2. Create a **private** repo via the GitHub API (`POST /user/repos`, `"private": true`).
3. `git init`, initial commit, `git remote add origin`, `git push -u origin main`.
4. Set `user.name` to the author name and `user.email` to the GitHub account email, scoped locally to the repo.

If repo creation fails (offline, no token, name taken), still create the project locally with a full git repo and mark it **"Not synced"** with a **Connect to GitHub** action. Local-only projects must be fully functional — GitHub is not a prerequisite for writing.

### 6.3 Authentication

In order of preference:

1. **Existing credentials.** Run `git ls-remote` against a test URL. If it succeeds — SSH keys or an existing credential helper are already configured — do nothing further. On a machine where you already use git, this path costs the user zero setup.
2. **Fine-grained Personal Access Token.** Onboarding links directly to the GitHub token creation page with redrafterd scopes stated plainly (repo contents read/write, repo administration for creating repos). Store in the **macOS Keychain**, never in a plist, never in `project.json`, never in `.git/config`.
3. Skip OAuth device flow for v1. It's meaningful work for a single-user tool where a PAT is a two-minute setup.

Provide a **Test Connection** button in Settings that runs `git ls-remote` and reports the actual result. Never store a token that hasn't been verified.

### 6.4 Commit triggers

All commits are automatic and silent. No commit dialog ever.

| Trigger | Message format |
|---|---|
| 90 s after last keystroke (debounced) | `autosave — 3 files, +412 words` |
| App loses focus / window closes | `autosave (focus lost)` |
| Project closed | `session end — +1,840 words` |
| Before any export | `pre-export` |
| Manual ⌘S | `checkpoint` (+ optional user label) |

Append a machine identifier as a commit trailer so the timeline is legible later:

```
autosave — 3 files, +412 words

Machine: Josiah-MacBook-Pro
```

Skip entirely when `git status --porcelain` is empty. Never create empty commits. Run `git gc --auto` on project close.

Local-file mode reuses this exact trigger table for snapshots (§7.2).

### 6.5 Sync loop

| Event | Action |
|---|---|
| Project open | `fetch`, then integrate (6.6) |
| Window regains focus | `fetch`, then integrate |
| Every 3 minutes while open | `fetch`, then integrate |
| ~30 s after any commit (debounced) | `push` |
| Project close | commit, integrate, `push`, wait for completion |

**Push aggressively.** The divergence window is the entire source of merge conflicts, and a 30-second push cadence keeps it near zero. In practice, closing the laptop lid and opening the desktop will almost always be a clean fast-forward.

All network operations run off the main thread and fail silently into a status indicator. Being offline is normal, not an error — queue and retry with backoff.

**Status indicator** in the toolbar, one glanceable control:
`Synced` · `Syncing…` · `Offline — 4 commits pending` · `Conflict — action needed` · `Not synced to GitHub`

### 6.6 Integration strategy

After fetch, compare local `HEAD` to `origin/main`:

- **Identical** — nothing to do.
- **Local behind** — fast-forward. If a file currently open in the editor changed, apply the reload rules in section 8.2.
- **Local ahead** — push (subject to debounce).
- **Diverged** — `git merge origin/main` (merge, not rebase: autosave commits are noisy and rewriting them mid-session is confusing and unsafe). If the merge is clean, commit it as `merge from <machine>` and push.
- **Diverged with conflicts** — enter conflict state, section 6.7.

Never merge while the editor has unsaved buffer contents — commit first, always. Never run integration during an active typing burst; defer to the next idle window.

### 6.7 Conflict resolution

Because of one-paragraph-per-line, a conflict means the same paragraph was edited on both machines without an intervening sync. This should be rare and, when it happens, small.

v1 handles it **per-file**, not per-hunk. No three-way merge editor — that's a large build for an uncommon event, and can come later if the simple flow proves insufficient.

Conflict sheet, listing every conflicted file:

> **2 scenes changed on both machines**
>
> `Manuscript/02 The First Hour/02 Code Blue.md`
> Mine — edited 14 minutes ago on Josiah-Mac-Studio
> Theirs — edited 2 hours ago on Josiah-MacBook-Pro
> [Compare] [Keep Mine] [Keep Theirs] [Keep Both]

- **Compare** — side-by-side diff, same view used by History.
- **Keep Mine** / **Keep Theirs** — `git checkout --ours` / `--theirs`.
- **Keep Both** — keep mine in place, write theirs as `<name> (from MacBook Pro 2026-08-17).md` in the same folder, re-sequenced into the binder so it's visible and can be reconciled by reading.

**Keep Both is the safe default** and should be the primary button. Losing a paragraph silently is a far worse outcome than a duplicate file the writer deletes in ten seconds.

Once all files are resolved: `git add -A`, commit as `resolve conflicts from <machine>`, push.

### 6.8 History UI

**History** panel in the inspector, scoped to the open scene:

- Commits touching this file (`git log --follow`), showing relative time, word delta, machine name.
- Selecting a version shows a two-pane diff with word-level highlighting.
- Restore actions:
  - **Restore as copy** — writes alongside as `<name> (restored 2026-08-17).md`, inserted into the binder. Primary button.
  - **Restore** — overwrites the current file, committing current state first, always.

Project-wide **Timeline** view: all commits, filterable by day and machine, with word counts. Whole-commit restore is implemented as "export this version to a folder," not as an in-place rollback.

This panel and its diff component are shared with Local-file mode — see §9.1.

### 6.9 Cloning to a second machine

**Add Existing Project** offers two paths:

1. **Paste a clone URL** — always works, no API dependency. Baseline implementation.
2. **Pick from your GitHub repos** — if a token is present, list repos and filter to those containing a `project.json` at root. Nicer, strictly optional.

Clone into the default projects location, read `project.json`, open. Nothing else redrafterd.

---

## 7. Local-file mode: version control and sync

### 7.1 Model

A Local-file project is a plain folder with no `.git`. Version history is a sequence of full-tree snapshots under `History/`, each a normal, independently readable copy of the project at one point in time. There's no repository object model, no remote, no push/fetch — moving files between machines is entirely the cloud-sync client's job, running exactly as it already does for every other file on the writer's Mac.

This means the app cannot promise a unified timeline the way Git mode does: two machines writing near-simultaneously produce two overlapping sets of snapshots, reconciled only by whatever the cloud client does when the same path changes on both ends. For a single writer working on one file at a time, this is rare and low-stakes — the same tradeoff already accepted for every other file in a Box or Drive folder.

### 7.2 Snapshot mechanism

Uses the same trigger table as Git-mode commits (§6.4: debounced 90 s after typing, focus loss, session end, pre-export, manual ⌘S):

1. Skip if nothing changed since the last snapshot (compare content, not mtime — cloud clients touch mtimes on sync).
2. Create `History/<local ISO 8601 timestamp> <machine name>/`.
3. Populate it with the current `Manuscript/`, `FrontMatter/`, `BackMatter/`, `Resources/`, and `project.json`.
4. On APFS, use `copyfile(3)` with `COPYFILE_CLONE` for the whole tree — near-instant, and a cloned file only consumes additional disk space once it diverges from the original. Fall back to a plain recursive copy on non-APFS volumes.

A snapshot never mutates a previous one. Deleting or corrupting the working tree cannot touch `History/`.

### 7.3 Retention and pruning

Full-density snapshots accumulate fast at a 90-second cadence. Thin on project close, Time Machine–style:

- Keep everything from the last 48 hours.
- Beyond 48 hours, keep one per day for 30 days.
- Beyond 30 days, keep one per week, indefinitely.
- Never prune a **checkpoint** (manual ⌘S) or **pre-export** snapshot — those are the ones a writer is most likely to reach for later.

Thinning deletes whole snapshot folders; it never edits file contents inside a kept snapshot. Runs off the main thread; never blocks writing.

### 7.4 History and diff UI

Same panel, same two-pane word-level diff component as Git mode (§6.8) — it already operates on two strings of file content, so it doesn't care whether they came from `git show` or from reading two files under `History/`. See §9.1.

- List entries: for the open scene, every snapshot where that scene's content differs from the previous kept snapshot (matched by the scene's internal `id`, §4.4, so renames don't break the trail), showing relative time, word delta, machine name.
- Restore actions identical to Git mode: **Restore as copy** (primary) and **Restore** (overwrite, snapshotting current state first, always).

Project-wide Timeline view: same as §6.8, sourced from `History/` folder names instead of `git log`.

### 7.5 Conflicted copies

No merge engine — the app doesn't own sync, so it can't intervene mid-write the way it can with git. Instead, watch for the conflicted-copy naming patterns each provider uses (Dropbox: `<name> (<user>'s conflicted copy <date>).md`; iCloud: `<name> 2.md`; Box and OneDrive have their own equivalents — Appendix B) and surface a banner:

> **A file may have synced with a conflict**
> `Manuscript/02 The First Hour/02 Code Blue 2.md` looks like a cloud-sync conflict copy.
> [Compare with original] [Keep this one] [Delete]

**Compare** reuses the same diff view. This is best-effort, not a guarantee — the app can't know every provider's naming scheme, so the Settings status area always shows **when `History/` last received a snapshot from another machine**, which is the reliable signal that something changed elsewhere.

### 7.6 Sync status and machine awareness

No fetch/push, so the status control shows something narrower than Git mode's:

`Saved` · `Saved — syncing via Box` (provider name detected from the path) · `Saved — not in a synced folder` · `Conflict copy detected`

Provider detection: check whether the resolved project path is under `~/Library/CloudStorage/<Provider>-*`, `~/Dropbox`, `~/Google Drive`, `~/OneDrive`, or `~/Library/Mobile Documents/`, and name it. Display-only — the app never calls a provider API, only reads the path.

---

## 8. Safety and local resilience

Applies to both modes except where noted.

### 8.1 Local snapshot fallback (Git mode only)

If git is unavailable, a Git-mode project falls back to the same snapshot mechanism Local-file mode uses natively (§7.2): timestamped whole-tree copies under `History/` on the same triggers as commits. Degraded but never data-losing — and since the fallback data lands in the shape Local-file mode already knows how to read, restoring from it needs no separate code path. Surface a persistent, non-blocking banner explaining what's missing and how to fix it.

### 8.2 Filesystem watching

Watch the working tree with `FSEventStream`, debounced 500 ms, in both modes. In Git mode, external changes ordinarily come from the app's own git operations; in Local-file mode they may legitimately come from the cloud-sync client writing files in the background. The reload rules are the same either way:

- Changed file not open in editor → reload silently, refresh binder.
- Open with no unsaved edits → reload silently, preserve cursor by offset.
- Open with unsaved edits → never clobber. Inline bar: *"This scene changed."* [Keep Mine] [Load Theirs] [Compare].

### 8.3 Concurrent-editing warning

There's no lock file in either mode. On project open and on focus:

- **Git mode** — check whether `origin/main` has commits from a *different* machine within the last 5 minutes.
- **Local-file mode** — check whether the newest folder in `History/` was written by a *different* machine within the last 5 minutes.

Same warning sheet either way:

> **The Last Shift may be open on Josiah-MacBook-Pro**
> Changes were [pushed/saved] 40 seconds ago. Editing in both places at once can create conflicts.
> [Continue] [Cancel]

Same protective value as a lock file, no extra file, no conflict surface.

### 8.4 Atomic writes

Every file write in the app: write to a temp file in the same directory, `fsync`, then atomically `rename` over the target. Never truncate an existing file. This is non-negotiable and applies to scene saves, `project.json`, snapshot creation, and generated matter alike.

---

## 9. Application architecture

```
DrafterApp
├── ProjectStore          — owns the open project; file I/O; FSEvents; in-memory tree
│   ├── ProjectMetadata   — project.json read/write
│   ├── BinderTree        — folder/file model, ordering, rename/reorder/create/delete
│   └── SceneDocument     — text + parsed front matter, dirty tracking, autosave
├── VersioningService     — protocol: checkpoint(), history(for:), diff(a:b:), restore(...) (§9.1)
│   ├── GitService          — subprocess wrapper: commit, fetch, merge, push, log, diff (Git mode)
│   │   ├── SyncCoordinator   — timers, debounce, integration strategy, status state machine
│   │   ├── ConflictResolver  — detect, present, resolve, commit
│   │   └── CredentialStore   — Keychain access, GitHub API for repo create/list
│   └── SnapshotService     — whole-tree snapshot create/list/diff/restore, retention pruning,
│                              provider detection (Local-file mode; also the Git-mode
│                              git-unavailable fallback, §8.1)
├── CompileService        — assembly → pandoc → EPUB / typst → PDF
│   ├── ManuscriptAssembler
│   ├── FrontMatterBuilder
│   └── ExportTargets     — EPUB, PDF, DOCX
└── UI (SwiftUI)
    ├── BinderView · EditorView · InspectorView
    ├── CompileSheet · ConflictSheet · ConflictedCopyBanner
    └── VersionStatusControl
```

### 9.1 VersioningService

A small protocol — `checkpoint()`, `history(for: SceneID)`, `diff(a:b:)`, `restore(...)` — that `HistoryPanel`, `TimelineView`, and the compare views code against, so the UI layer doesn't know or care which mode a project is in. `GitService` and `SnapshotService` are its two conformances. This is what lets §6.8/§7.4's History UI and the conflict/conflicted-copy compare views be literally the same SwiftUI code in both modes.

**Threading:** one serial queue per project for all git operations — never concurrent git in the same working tree. `SnapshotService` likewise serializes writes to `History/` per project — never concurrent snapshot creation and pruning. Subprocess wrapper captures stdout/stderr and surfaces non-zero exits as readable errors. Nothing versioning-related ever blocks the editor.

**State machines.** Git mode: `idle → fetching → merging → conflicted → pushing → idle`, plus `offline`. Conflicted is a terminal state until user action. Local-file mode is simpler, with no network: `idle → snapshotting → idle`, plus a non-blocking `conflictedCopyDetected` flag. Model both explicitly rather than with scattered booleans.

---

## 10. UI specification

### 10.1 Window layout

Three panes, all collapsible:

```
┌──────────┬─────────────────────────────┬────────────┐
│ Binder   │ Editor                      │ Inspector  │
│          │                             │            │
│ ▸ 01 …   │   measured column, centered │  Synopsis  │
│ ▾ 02 …   │                             │  Status    │
│   Scene  │                             │  Targets   │
│   Scene  │                             │  History   │
└──────────┴─────────────────────────────┴────────────┘
  ~240pt              flexible               ~280pt
```

Toolbar: version status control (right), compile button, pane toggles.

### 10.2 Binder

- `List` + `OutlineGroup` over the on-disk tree.
- Drag to reorder within and across chapters → renames per §4.3 (`git mv` in Git mode, plain move in Local-file mode).
- Inline rename on double-click or Return.
- Context menu: New Scene, New Chapter, Duplicate, Checkpoint, Reveal in Finder, Exclude from Compile, Move to Trash.
- Per-row: display name, word count (right-aligned, secondary), status dot.
- Chapter rows show aggregate word count.
- Sections: Manuscript, Front Matter, Back Matter, Notes — Notes de-emphasized.

### 10.3 Editor

In priority order:

1. **Performance at length** — a 5,000-word scene types and scrolls without hitching.
2. **Measured column** — configurable max line width (default ~68 characters), centered, generous margins. This affects daily writing comfort more than any other setting.
3. **No hard wrapping, ever** (§4.7). Soft wrap only.
4. **Typewriter scrolling** — toggleable, caret held at a fixed vertical position (default 45%).
5. **Syntax affordances, not rendering** — render `*italic*` in actual italic while leaving asterisks visible but dimmed. Same for `**bold**` and `#`. Implemented via `NSTextStorage` attribute application. Keeps the file honest and costs a fraction of a rich-text engine.
6. **⌘I / ⌘B** wrap selection or insert paired markers.
7. **Focus mode** (v1.5) — dim all paragraphs except the caret's.
8. **Find & Replace** — in-document (⌘F) and project-wide (⇧⌘F) with a results list that jumps to scene and offset.
9. **Autosave** — disk write 2 s after last keystroke and on blur. No save button.

Preferences: font family, size, line height, measured width, theme (light/dark/sepia), typewriter scrolling.

### 10.4 Inspector

- **Scene** — synopsis, status picker, compile toggle, scene notes.
- **Targets** — session words, scene/chapter/project totals against `target.words` with progress bar. Session count resets on open.
- **History** — §6.8 (Git mode) / §7.4 (Local-file mode) — same panel either way.

### 10.5 Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N / ⇧⌘N | New scene / new chapter |
| ⌘S | Checkpoint (commit now / snapshot now) |
| ⌥⌘S | Sync now (Git mode: fetch, merge, push) / Snapshot now (Local-file mode) |
| ⌘I / ⌘B | Italic / bold |
| ⌘F / ⇧⌘F | Find in scene / in project |
| ⌘⌥E | Compile |
| ⌃⌘F | Composition mode |
| ⌘1 / ⌘2 / ⌘3 | Toggle binder / editor focus / inspector |

---

## 11. Compile pipeline

### 11.1 Assembly

`ManuscriptAssembler` walks `Manuscript/` in prefix order, producing one markdown stream:

1. Skip files with `compile: false`, everything in `Notes/`, any unresolved conflict artifacts, and (Local-file mode) anything under `History/`.
2. Strip YAML front matter from every scene.
3. Per chapter folder:
   - Emit a heading from `compile.chapterTitleFormat`. Tokens: `{n}` (1-based index), `{n_word}` (`One`, `Two`, …), `{title}` (folder name minus prefix). `none` emits no heading.
   - Join scenes with `compile.sceneSeparator` on its own line, blank lines either side.
4. A loose `.md` at `Manuscript/` root becomes its own chapter, filename as `{title}`.
5. Front and back matter assemble the same way but receive no generated headings — they carry their own `#` headers.

Write output to `Build/` (excluded from Git-mode commits and Local-file-mode snapshots) and keep it after export, exposed via a **Show assembled markdown** debug command. It is the single most useful artifact when an export looks wrong.

### 11.2 Front and back matter generation

Generated from `project.json` at project creation as **editable markdown files**, never regenerated at compile time — so hand edits are permanent. Provide a per-file **Regenerate from template** command with confirmation.

**Title Page**
```markdown
# {title}
{subtitle}

{author}
```

**Copyright**
```markdown
Copyright © {copyrightYear} by {author}

All rights reserved. No part of this book may be reproduced in any
form without written permission from the author, except brief
quotations used in a book review.

This is a work of fiction. Names, characters, places, and incidents
are products of the author's imagination or are used fictitiously.
Any resemblance to actual persons, living or dead, events, or
locales is entirely coincidental.

{isbn_line}
```

**Also By**, **Dedication**, **About the Author**, **Newsletter** — stubs with placeholder lines. Ordering by numeric prefix as elsewhere.

### 11.3 EPUB target

```
pandoc Build/assembled.md \
  --from=markdown+smart \
  --to=epub3 \
  --metadata-file=Build/meta.yaml \
  --epub-cover-image=Resources/cover.jpg \
  --css=epub.css \
  --toc --toc-depth=1 \
  --split-level=1 \
  -o "The Last Shift.epub"
```

`meta.yaml` generated from `project.json`: title, subtitle, creator, publisher, date, language, description, rights, identifier (ISBN if present, else a stable UUID from `project.id`).

`epub.css` requirements, modeled on real compiled EPUBs (Scrivener exports of finished novels and short stories) rather than assumed defaults:

- No forced font, justification, or hyphenation — leave all three to the reader's device/app settings, which is also friendlier to accessibility than overriding them
- Indent only a paragraph that directly follows another paragraph (`p + p`), not the first paragraph after a heading or scene break — matches the reference exports and is more robust than enumerating every element a paragraph might follow
- Scene break (`* * *` → `<hr>`): blank space, no glyph, no rule
- Chapter headings: page break before, centered, uppercase, underlined, ample space above
- `em`/`rem` throughout, no fixed pixels

Ship `epub.css` as an editable file in Application Support with a **Reveal stylesheet** command. It will need tuning.

Validate with `epubcheck` when available and surface results — KDP rejects on errors that are trivial to fix beforehand.

### 11.4 Print PDF target

```
pandoc Build/assembled.md --from=markdown+smart --to=typst -o Build/body.typ
typst compile Build/main.typ "The Last Shift - interior.pdf"
```

`main.typ` generated from a template, parameterized by `project.print`.

| Concern | Specification |
|---|---|
| Trim sizes | 5×8, 5.25×8, 5.5×8.5, 6×9 |
| Margins | Mirrored. Outside 0.5″, top 0.8″, bottom 1.0″ — measured off a real compiled print PDF (Scrivener export of a finished novel) rather than assumed |
| Gutter | By page count: 0.375″ (≤150), 0.5″ (151–300), 0.625″ (301–500), 0.75″ (501–700) |
| Bleed | None for interior |
| Body | Serif, 11–11.5 pt, leading ~1.46 (16.8pt line pitch measured off the reference) |
| Paragraphs | First after heading/break flush; others indented 1.2 em; no inter-paragraph space |
| Chapter openers | Start on the next page regardless of recto/verso by default (configurable to force recto), drop ~30% page, drop folio |
| Running heads | Verso author, recto title. Small caps |
| Page numbers | Bottom center or outer. Front matter roman or unnumbered; body starts at arabic 1 |
| Widows/orphans | Suppressed |
| Scene break | Plain `* * *`, no ornament — matches the reference; at a page break, substitute blank line plus indent suppression so the break isn't lost |

Gutter depends on final page count, which depends on layout — so compile once, read the page count, and recompile if it crosses a threshold. Two passes, automatic, invisible to the user.

### 11.5 DOCX fallback

```
pandoc Build/assembled.md --from=markdown+smart --to=docx \
  --reference-doc=reference.docx -o manuscript.docx
```

Ship a `reference.docx` with sane Normal and Heading 1 styles. For sending to an editor, and as an escape hatch when print layout needs manual work.

### 11.6 Compile sheet

One sheet, no wizard:

- Target: **EPUB** / **Print PDF** / **DOCX**
- Output location (default `~/Desktop`, remembered per project)
- Front matter / back matter toggles
- Chapter title format with live preview of the first heading
- Scene separator field
- Print only: trim size, body font, point size
- Live estimate: word count, and for print, estimated page count
- **Compile**, then a success row with **Reveal in Finder** and **Open**

On failure, show pandoc/typst stderr verbatim in a disclosure triangle. Never swallow it behind a generic message.

---

## 12. Settings

| Pane | Contents |
|---|---|
| General | Projects location, default author name, reopen last project on launch |
| Editor | Font, size, line height, measured width, theme, typewriter scrolling, focus mode |
| Version Control | Mode (read-only, set at creation). **Git mode:** GitHub account status, Test Connection, token management, push/fetch intervals, per-project remote URL, Disconnect from GitHub. **Local-file mode:** detected cloud provider (if any), History location, retention policy, last snapshot time, **Snapshot Now**, **Open History in Finder** |
| Versioning | Autosave interval, autocommit/autosnapshot debounce, history size (Git: `git count-objects -vH`; Local-file: `History/` folder size), **Run Maintenance** (Git: `git gc`; Local-file: force-prune per retention policy) |
| Tools | Resolved paths for git, pandoc, typst, epubcheck — status indicator and override field each |

---

## 13. Build phases

**M0 — Skeleton (usable: browse)**
Create/open project folder. Binder tree from disk. Read-only scene display. `project.json` read/write.

**M1 — Editing (usable: write a book)**
`NSTextView` wrapper, autosave with atomic writes, no hard wrapping, word counts, create/rename/delete/reorder with prefix re-sequencing, measured column, typewriter scrolling, ⌘I/⌘B.

**M2 — Local git (usable: safely)**
`GitService`, repo init, commit triggers, log, diff, History panel, restore. No remote yet. **This milestone alone makes the app safe to write in.**

**M3 — Git mode: GitHub sync (usable: on two machines)**
Keychain credentials, GitHub API repo creation, clone existing, fetch/merge/push loop, sync status control, conflict detection and the per-file resolution sheet, concurrent-editing warning, FSEvents reload rules.

**M4 — Local-file mode**
`SnapshotService` (create/list/diff/restore), retention pruning, cloud-provider detection, conflicted-copy banner, the onboarding mode picker (§5). Extract `VersioningService` from `GitService` so the History/Timeline UI built in M2 doesn't fork — `GitService` and `SnapshotService` become its two conformances.

**M5 — Metadata & matter**
Project metadata editor, front/back matter generation, regenerate command, targets panel.

**M6 — EPUB export**
Assembler, pandoc invocation, `meta.yaml`, `epub.css`, compile sheet, epubcheck.

**M7 — Print export**
Typst template, trim sizes, mirrored margins, two-pass gutter, running heads, chapter openers, DOCX fallback.

**M8 — Polish**
Project-wide find & replace, focus mode, composition mode, settings panes, error-handling audit, onboarding.

---

## 14. Failure modes to handle explicitly

### 14.1 Git-mode working copy placed in a sync folder

The one failure that can silently destroy a Git-mode repository. A `.git` directory inside Box, Dropbox, or iCloud Drive will eventually corrupt — thousands of small mutating files, no atomic directory semantics, placeholder eviction, and conflict copies written *into* the object store. This applies **only to Git mode** — Local-file mode has no `.git` directory to threaten, and deliberately expects this placement (§4.1).

**Hard-block it, for Git mode only.** On project create or open, resolve the real path and refuse any location under `~/Library/CloudStorage/`, `~/Dropbox`, `~/Google Drive`, `~/OneDrive`, or `~/Library/Mobile Documents/`. Explain why in one sentence and offer to relocate. Do not make this a dismissible warning.

### 14.2 Everything else

1. **Project folder moved or renamed while open** — FSEvents reports it. Halt writes, prompt to re-locate. Never write to a stale path.
2. **Push rejected (non-fast-forward)** — fetch, integrate per §6.6, retry once. If it fails again, surface it rather than looping. (Git mode.)
3. **Merge conflict** — §6.7. (Git mode.)
4. **Token expired or revoked** — detect the auth failure specifically (not as generic network failure), set status to `Not synced`, prompt to re-authenticate. Never lose work over it. (Git mode.)
5. **Offline for days** — commits queue locally and push when connectivity returns. Show pending count. This is a normal state, not an error. (Git mode.)
6. **History grows large from cover images** — a few MB of JPEG is fine. Git mode: if `Resources/` exceeds ~50 MB, suggest Git LFS in Settings, but don't redrafter it for v1. Local-file mode: APFS cloning (§7.2) keeps unchanged images from costing extra space per snapshot; if `History/` still exceeds a threshold (~2 GB), surface its size in Settings and suggest running maintenance.
7. **Two app instances open the same project** — check for an existing window bound to that path before opening.
8. **Non-UTF8 or BOM-prefixed files** — normalize on read, always write UTF-8 without BOM.
9. **Illegal filename characters** (`: / \ ? * " < > |`) — sanitize on rename.
10. **Very long scene (>20k words)** — must still perform. Test with a pathological file.
11. **git unavailable (Git mode)** — snapshot fallback (§8.1), persistent remediation banner.
12. **Cloud provider writes a conflicted-copy file (Local-file mode)** — §7.5, non-blocking banner.
13. **pandoc/typst missing or failing** — surface stderr verbatim, keep `Build/assembled.md` so the user can compile by hand.
14. **Disk full mid-save** — atomic write-and-rename (§8.4) makes this survivable.

---

## 15. Testing checklist

- Reorder 40 scenes across 12 chapters; confirm prefixes stay dense and history still tracks moved files in both modes.
- Write on machine A, close, open on machine B — confirm a clean fast-forward (Git mode) or a fully-synced folder with no divergence (Local-file mode, single-writer case) with no user-visible friction.
- Force divergence (Git mode): edit *different* paragraphs of the same scene on both machines while offline, reconnect, confirm a clean automatic merge with no prompt.
- Force a true conflict (Git mode): edit the *same* paragraph on both machines while offline, reconnect, confirm the conflict sheet and all three resolutions, especially Keep Both.
- Attempt to create a Git-mode project inside Box Drive; confirm it is refused.
- Create a Local-file project inside `~/Library/CloudStorage/Box-Box/`; confirm snapshots appear and are readable in Finder with the app closed.
- Diff two Local-file snapshots of the same scene; confirm word-level highlighting matches Git mode's.
- Force retention pruning with 72 hours of synthetic snapshots; confirm the thinning schedule and that checkpoint/pre-export snapshots survive.
- Simulate a Dropbox/iCloud conflicted-copy filename appearing via FSEvents; confirm the banner appears and Compare/Keep/Delete all work.
- Rename a scene in Local-file mode; confirm its History entries still resolve via internal `id` rather than breaking.
- Move a Local-file project out of a cloud folder mid-session; confirm the app keeps working with local-only history and the status control updates.
- Kill the app mid-typing (`kill -9`); confirm no truncated files and at most 2 s of lost work, in either mode.
- Revoke the GitHub token mid-session; confirm writing continues uninterrupted and status reflects reality.
- Delete a Git-mode project locally; clone from GitHub; confirm a byte-identical working tree.
- Restore a scene from a Local-file snapshot with no network; confirm full recovery reading only the `History/` folder.
- Compile a 45k-word manuscript to EPUB; validate with epubcheck; open in Kindle Previewer.
- Compile to print PDF at 5×8; verify mirrored margins, correct gutter, recto chapter openers, running heads, no widows.

---

## 16. Deferred (post-v1)

Three-way merge editor with per-hunk resolution (Git mode); compile presets saved per project; multiple manuscripts in one repo (for series); word-count history chart sourced from git log / snapshot history; scene-level time tracking; GitHub Releases as export archive; self-hosted or NAS remote as a first-class alternative to GitHub; converting a project between Git mode and Local-file mode in place.

---

## Appendix A — git command reference

| Purpose | Command |
|---|---|
| Init | `git init -b main` |
| Local identity | `git config user.name "…"` / `user.email "…"` |
| Check for changes | `git status --porcelain` |
| Stage all | `git add -A` |
| Commit | `git commit -m "<message>"` |
| Add remote | `git remote add origin <url>` |
| First push | `git push -u origin main` |
| Fetch | `git fetch origin` |
| Compare to remote | `git rev-list --left-right --count HEAD...origin/main` |
| Fast-forward | `git merge --ff-only origin/main` |
| Merge | `git merge origin/main` |
| List conflicts | `git diff --name-only --diff-filter=U` |
| Resolve | `git checkout --ours <path>` / `--theirs <path>` |
| Rename tracked file | `git mv <old> <new>` |
| Log for a file | `git log --follow --format=%H%x1f%at%x1f%s%x1f%an -- "<path>"` |
| File at commit | `git show <sha>:"<path>"` |
| Diff versions | `git diff <sha1> <sha2> -- "<path>"` |
| Repo size | `git count-objects -vH` |
| Maintenance | `git gc --auto` |

Use `%x1f` (unit separator) as the log field delimiter — commit subjects can contain nearly anything else.

Always pass `GIT_TERMINAL_PROMPT=0` in the subprocess environment. A git operation must never hang waiting on an invisible credential prompt.

## Appendix B — local-file snapshot reference

| Concern | Specification |
|---|---|
| Snapshot folder name | `<local ISO 8601 timestamp, colon-safe> <machine name>`, e.g. `2026-08-18 14-32-05 Josiah-MacBook-Pro` |
| Copy mechanism | `copyfile(3)` with `COPYFILE_CLONE` on APFS; recursive copy on other filesystems |
| Change detection | Compare file content hashes against the newest existing snapshot; skip the snapshot entirely if identical |
| Scene identity across renames | Internal `id` in YAML front matter (§4.4), not path |
| Retention | Keep everything ≤48h old; 1/day for the next 30 days; 1/week beyond that; never prune a checkpoint or pre-export snapshot |
| Conflicted-copy patterns watched | Dropbox: `<name> (<user>'s conflicted copy <date>).md` · iCloud: `<name> 2.md` · Box: `<name> (Conflicted copy <date>).md` · OneDrive: `<name>-<machine>.md` |
| Provider detection paths | `~/Library/CloudStorage/Box-*`, `~/Library/CloudStorage/GoogleDrive-*`, `~/Library/CloudStorage/OneDrive-*`, `~/Dropbox`, `~/Library/Mobile Documents/com~apple~CloudDocs` |

## Appendix C — word counting

Count the markdown source with these removed: YAML front matter, `#` markers, `*`/`**` emphasis markers, scene separator lines, HTML comments. Split on whitespace; hyphenated compounds count as one; exclude standalone punctuation tokens.

Compute per-scene on save (debounced), cache in memory, aggregate upward for chapter and project totals. Never recompute the project on every keystroke.
