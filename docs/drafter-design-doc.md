# Drafter — Design Document

*Version 2 — GitHub-backed sync architecture*

A minimal macOS writing app: chapter/scene organization, distraction-light markdown editing, automatic version control, sync across machines via private GitHub repositories, and one-click export to EPUB and print-ready PDF.

---

## 1. Purpose and scope

### 1.1 What this replaces

Scrivener, used narrowly: binder-style chapter/scene organization, plain prose editing, snapshot versioning as a safety net, and compile-to-EPUB / compile-to-print. Nothing else.

### 1.2 Goals

1. **Chapter/scene file structure** legible in Finder and durable if the app disappears.
2. **Fast, quiet markdown editing** with a minimal formatting surface.
3. **Automatic version control** — the writer never thinks about it, never loses work, and has a unified history across all machines.
4. **Seamless two-machine workflow** via a private GitHub repo per book.
5. **Repeatable export** to EPUB (KDP/KU) and print-ready PDF (KDP paperback), including generated front and back matter.
6. **Independent backup** to Box Drive that redrafters no tooling to recover from.

### 1.3 Explicit non-goals

Do not build: corkboard/index cards, split editor, research folder with embedded PDFs/images, inline annotations and comments, custom metadata fields, collections/saved searches, scriptwriting mode, collaboration or multi-author workflows, iOS app, Scrivener import.

If a feature is not in section 8 or 9, it is out of scope for v1.

### 1.4 Design constraints

- **macOS only.** Minimum macOS 14. Single user, personal-use app — no App Store distribution, no App Sandbox (the app shells out to `git`, `pandoc`, and `typst`, which sandboxing complicates for little benefit).
- **Working copies live on local disk**, not in any cloud-synced folder. Sync happens through git, never through a filesystem sync client. This is the central architectural decision — see section 5.
- **Plain files are the source of truth.** The app is a view onto a git working tree. If the app breaks, the manuscript is a tree of `.md` files. If the machine dies, the manuscript is on GitHub and in Box.

---

## 2. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| UI shell | SwiftUI (macOS 14+) | Fast to build, adequate for a three-pane app |
| Prose editor | `NSTextView` wrapped in `NSViewRepresentable` | SwiftUI's `TextEditor` degrades on long documents and gives poor control over cursor, selection, typewriter scrolling |
| Data model | Plain files on disk + in-memory model | **No Core Data, no SwiftData.** The filesystem is the database |
| Version control & sync | `git` invoked as a subprocess; private GitHub repo per book | Section 5 |
| Credentials | macOS Keychain via `Security` framework | Section 5.3 |
| Markdown → EPUB | `pandoc` | Mature EPUB3 writer with metadata, TOC, CSS support |
| Markdown → print PDF | `pandoc` → Typst → PDF | Typst is a single ~30 MB binary with excellent book layout; avoids a 5 GB MacTeX dependency |
| Fallback print path | `pandoc` → `.docx` with reference doc | Escape hatch for manual touch-up, and for sending to an editor |

### 2.1 Binary dependencies

Bundle `pandoc` and `typst` in `Drafter.app/Contents/Resources/bin/`. Resolve in order: bundled → user-configured path in Settings → `PATH` (`/opt/homebrew/bin`, `/usr/local/bin`). If unresolvable, disable export UI with a one-line remediation message rather than crashing.

Do **not** bundle `git` — macOS ships it via Command Line Tools. If `git --version` fails, prompt to run `xcode-select --install` and operate in a degraded read/write-only mode with snapshot fallback (section 6.7) until git is available.

---

## 3. Core concepts

- **Project** — one book. A local folder that is also a git working tree, with a private GitHub repo as its remote.
- **Chapter** — a subfolder of `Manuscript/`.
- **Scene** — a `.md` file inside a chapter folder.
- **Commit** — an automatic, silent version checkpoint.
- **Sync** — fetch, fast-forward or merge, and push. Automatic and continuous.
- **Compile** — the transformation of a project into an EPUB or PDF.

---

## 4. On-disk project format

### 4.1 Location

Working copies live at `~/Documents/Drafter/Projects/<Book Name>/` by default (configurable, but the app must **refuse** a location inside `~/Library/CloudStorage/`, `~/Dropbox`, `~/Google Drive`, or `~/iCloud Drive` — see section 12.1). Box Drive holds backups only, written by the app, never edited in place.

### 4.2 Directory layout

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

**.gitignore**

```
.DS_Store
Build/
*.tmp
```

**.gitattributes**

```
* text=auto eol=lf
*.md text
*.json text
*.jpg binary
*.png binary
```

Normalizing to LF matters — it prevents whole-file diffs caused by line-ending drift between machines.

### 4.3 Ordering

**Numeric filename prefixes are the sole source of truth for order.** `01 `, `02 `, `03 ` … zero-padded to two digits (three if a chapter exceeds 99 scenes).

Rationale, now that git is the sync layer: a central `order` array in `project.json` would be rewritten by every reorder on every machine, making it the one file guaranteed to produce merge conflicts. Filename prefixes distribute ordering across the tree, so reorders conflict only when the *same* chapter was reordered on both machines.

Consequences:
- Reordering in the binder = renaming files. Batch the renames, then re-sequence the containing folder so prefixes stay dense (`01, 02, 03`, never `01, 03, 07`).
- Display name = filename minus prefix and extension.
- Tolerate missing or duplicate prefixes (sort by prefix, then alphabetically) and offer a "Re-sequence chapter" repair command.
- Use `git mv` for renames so history follows the file.

### 4.4 Per-scene metadata: YAML front matter

Scene metadata lives inside the scene file, for the same anti-conflict reason.

```markdown
---
synopsis: Sam takes over the board and finds Room Nine already occupied.
status: draft
compile: true
---

The board was wrong.
```

| Key | Type | Default | Meaning |
|---|---|---|---|
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
    "bodyFont": "EB Garamond",
    "bodyPointSize": 11.0,
    "leading": 1.35,
    "chapterOpensOn": "recto"
  }
}
```

`id` is generated once and used as a local cache key. The GitHub remote URL is the project's real identity; do not store it in `project.json` (it lives in `.git/config` already).

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

This is load-bearing for the whole sync design. Git diffs and merges line by line, so one-paragraph-per-line means git can cleanly merge edits to *different* paragraphs of the same scene, and only flags a conflict when both machines edited *the same paragraph*. Hard-wrapped prose would turn every edit into a cascade of reflowed lines and make automatic merging useless.

Blank line between paragraphs, as markdown redrafters. No trailing whitespace — strip on save.

---

## 5. Version control and sync

### 5.1 Model

One private GitHub repository per book. The local folder is an ordinary git working tree with `origin` pointing at that repo. There is nothing unusual about the setup — the app is a well-behaved git client with an opinionated automation layer on top.

Because the working copy is on local disk, all the pathologies of running git inside a sync client disappear: no placeholder files, no half-synced directories, no conflict copies inside `.git`.

History is unified across machines. There is one timeline.

### 5.2 Repository creation

On new project:

1. Slugify the title → `the-last-shift`. Let the user edit the repo name.
2. Create a **private** repo via the GitHub API (`POST /user/repos`, `"private": true`).
3. `git init`, initial commit, `git remote add origin`, `git push -u origin main`.
4. Set `user.name` to the author name and `user.email` to the GitHub account email, scoped locally to the repo.

If repo creation fails (offline, no token, name taken), still create the project locally with a full git repo and mark it **"Not synced"** with a **Connect to GitHub** action. Local-only projects must be fully functional — GitHub is not a prerequisite for writing.

### 5.3 Authentication

In order of preference:

1. **Existing credentials.** Run `git ls-remote` against a test URL. If it succeeds — SSH keys or an existing credential helper are already configured — do nothing further. On a machine where you already use git, this path costs the user zero setup.
2. **Fine-grained Personal Access Token.** Onboarding links directly to the GitHub token creation page with redrafterd scopes stated plainly (repo contents read/write, repo administration for creating repos). Store in the **macOS Keychain**, never in a plist, never in `project.json`, never in `.git/config`.
3. Skip OAuth device flow for v1. It's meaningful work for a single-user tool where a PAT is a two-minute setup.

Provide a **Test Connection** button in Settings that runs `git ls-remote` and reports the actual result. Never store a token that hasn't been verified.

### 5.4 Commit triggers

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

### 5.5 Sync loop

| Event | Action |
|---|---|
| Project open | `fetch`, then integrate (5.6) |
| Window regains focus | `fetch`, then integrate |
| Every 3 minutes while open | `fetch`, then integrate |
| ~30 s after any commit (debounced) | `push` |
| Project close | commit, integrate, `push`, wait for completion |

**Push aggressively.** The divergence window is the entire source of merge conflicts, and a 30-second push cadence keeps it near zero. In practice, closing the laptop lid and opening the desktop will almost always be a clean fast-forward.

All network operations run off the main thread and fail silently into a status indicator. Being offline is normal, not an error — queue and retry with backoff.

**Status indicator** in the toolbar, one glanceable control:
`Synced` · `Syncing…` · `Offline — 4 commits pending` · `Conflict — action needed` · `Not synced to GitHub`

### 5.6 Integration strategy

After fetch, compare local `HEAD` to `origin/main`:

- **Identical** — nothing to do.
- **Local behind** — fast-forward. If a file currently open in the editor changed, apply the reload rules in section 6.3.
- **Local ahead** — push (subject to debounce).
- **Diverged** — `git merge origin/main` (merge, not rebase: autosave commits are noisy and rewriting them mid-session is confusing and unsafe). If the merge is clean, commit it as `merge from <machine>` and push.
- **Diverged with conflicts** — enter conflict state, section 5.7.

Never merge while the editor has unsaved buffer contents — commit first, always. Never run integration during an active typing burst; defer to the next idle window.

### 5.7 Conflict resolution

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

### 5.8 History UI

**History** panel in the inspector, scoped to the open scene:

- Commits touching this file (`git log --follow`), showing relative time, word delta, machine name.
- Selecting a version shows a two-pane diff with word-level highlighting.
- Restore actions:
  - **Restore as copy** — writes alongside as `<name> (restored 2026-08-17).md`, inserted into the binder. Primary button.
  - **Restore** — overwrites the current file, committing current state first, always.

Project-wide **Timeline** view: all commits, filterable by day and machine, with word counts. Whole-commit restore is implemented as "export this version to a folder," not as an in-place rollback.

### 5.9 Cloning to a second machine

**Add Existing Project** offers two paths:

1. **Paste a clone URL** — always works, no API dependency. Baseline implementation.
2. **Pick from your GitHub repos** — if a token is present, list repos and filter to those containing a `project.json` at root. Nicer, strictly optional.

Clone into the default projects location, read `project.json`, open. Nothing else redrafterd.

---

## 6. Backup, safety, and local resilience

### 6.1 Box Drive as backup

Two independent mechanisms, both writing to `~/Library/CloudStorage/Box-Box/Drafter Backups/<Book Name>/`. The app writes here; the user never opens projects from here.

**A. Working-tree mirror** — on project close, copy the current `.md` files, `project.json`, and `Resources/` (no `.git`) to `<...>/Current/`. Human-readable, recoverable with no tooling, and Box's own file versioning layers on top for free.

**B. Repo bundle** — weekly (and on demand), `git bundle create <Book>-2026-08-17.bundle --all`. This is the *entire repository including full history* as a single file. One file means no directory-sync risk whatsoever, and `git clone <file>.bundle` restores everything if GitHub were ever unavailable, deleted, or account-locked. Retain the last 8 bundles, prune older.

Mechanism A protects against "I need the words right now." Mechanism B protects against "GitHub is gone." They cover different failures; implement both.

Both run off the main thread and fail silently into the Settings status display. Backup failure must never block writing or exporting.

### 6.2 Local snapshot fallback

If git is unavailable, fall back to write-once timestamped copies under `Build/Snapshots/` (gitignored) on the same triggers as commits. Degraded but never data-losing. Surface a persistent, non-blocking banner explaining what's missing and how to fix it.

### 6.3 Filesystem watching

Watch the working tree with `FSEventStream`, debounced 500 ms. External changes now come from git operations rather than a sync client, but the rules are the same:

- Changed file not open in editor → reload silently, refresh binder.
- Open with no unsaved edits → reload silently, preserve cursor by offset.
- Open with unsaved edits → never clobber. Inline bar: *"This scene changed."* [Keep Mine] [Load Theirs] [Compare].

### 6.4 Concurrent-editing warning

There's no lock file. Instead, on project open and on focus, check whether `origin/main` has commits from a *different* machine within the last 5 minutes:

> **The Last Shift may be open on Josiah-MacBook-Pro**
> Changes were pushed 40 seconds ago. Editing in both places at once can create conflicts.
> [Continue] [Cancel]

Same protective value as a lock file, no extra file, no conflict surface.

### 6.5 Atomic writes

Every file write in the app: write to a temp file in the same directory, `fsync`, then atomically `rename` over the target. Never truncate an existing file. This is non-negotiable and applies to scene saves, `project.json`, and generated matter alike.

---

## 7. Application architecture

```
DrafterApp
├── ProjectStore          — owns the open project; file I/O; FSEvents; in-memory tree
│   ├── ProjectMetadata   — project.json read/write
│   ├── BinderTree        — folder/file model, ordering, rename/reorder/create/delete
│   └── SceneDocument     — text + parsed front matter, dirty tracking, autosave
├── GitService            — subprocess wrapper: commit, fetch, merge, push, log, diff
│   ├── SyncCoordinator   — timers, debounce, integration strategy, status state machine
│   ├── ConflictResolver  — detect, present, resolve, commit
│   └── CredentialStore   — Keychain access, GitHub API for repo create/list
├── BackupService         — Box mirror + git bundle scheduling
├── CompileService        — assembly → pandoc → EPUB / typst → PDF
│   ├── ManuscriptAssembler
│   ├── FrontMatterBuilder
│   └── ExportTargets     — EPUB, PDF, DOCX
└── UI (SwiftUI)
    ├── BinderView · EditorView · InspectorView
    ├── CompileSheet · ConflictSheet
    └── SyncStatusControl
```

**Threading:** one serial queue per project for all git operations — never concurrent git in the same working tree. Subprocess wrapper captures stdout/stderr and surfaces non-zero exits as readable errors. Nothing git-related ever blocks the editor.

**State machine for sync status** (`idle → fetching → merging → conflicted → pushing → idle`, plus `offline`). Conflicted is a terminal state until user action. Model this explicitly rather than with scattered booleans — it's the part most likely to become spaghetti.

---

## 8. UI specification

### 8.1 Window layout

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

Toolbar: sync status control (right), compile button, pane toggles.

### 8.2 Binder

- `List` + `OutlineGroup` over the on-disk tree.
- Drag to reorder within and across chapters → `git mv` renames (§4.3).
- Inline rename on double-click or Return.
- Context menu: New Scene, New Chapter, Duplicate, Checkpoint, Reveal in Finder, Exclude from Compile, Move to Trash.
- Per-row: display name, word count (right-aligned, secondary), status dot.
- Chapter rows show aggregate word count.
- Sections: Manuscript, Front Matter, Back Matter, Notes — Notes de-emphasized.

### 8.3 Editor

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

### 8.4 Inspector

- **Scene** — synopsis, status picker, compile toggle, scene notes.
- **Targets** — session words, scene/chapter/project totals against `target.words` with progress bar. Session count resets on open.
- **History** — §5.8.

### 8.5 Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N / ⇧⌘N | New scene / new chapter |
| ⌘S | Checkpoint (commit now) |
| ⌥⌘S | Sync now (fetch, merge, push) |
| ⌘I / ⌘B | Italic / bold |
| ⌘F / ⇧⌘F | Find in scene / in project |
| ⌘⌥E | Compile |
| ⌃⌘F | Composition mode |
| ⌘1 / ⌘2 / ⌘3 | Toggle binder / editor focus / inspector |

---

## 9. Compile pipeline

### 9.1 Assembly

`ManuscriptAssembler` walks `Manuscript/` in prefix order, producing one markdown stream:

1. Skip files with `compile: false`, everything in `Notes/`, and any unresolved conflict artifacts.
2. Strip YAML front matter from every scene.
3. Per chapter folder:
   - Emit a heading from `compile.chapterTitleFormat`. Tokens: `{n}` (1-based index), `{n_word}` (`One`, `Two`, …), `{title}` (folder name minus prefix). `none` emits no heading.
   - Join scenes with `compile.sceneSeparator` on its own line, blank lines either side.
4. A loose `.md` at `Manuscript/` root becomes its own chapter, filename as `{title}`.
5. Front and back matter assemble the same way but receive no generated headings — they carry their own `#` headers.

Write output to `Build/` (gitignored) and keep it after export, exposed via a **Show assembled markdown** debug command. It is the single most useful artifact when an export looks wrong.

### 9.2 Front and back matter generation

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

### 9.3 EPUB target

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

`epub.css` redrafterments:

- Serif body, justified, hyphenation on
- First paragraph after a heading or scene break: no indent. Subsequent: `text-indent: 1.2em`, no top margin
- Scene break (`* * *` → `<hr>`): centered ornament, generous vertical space, no rule
- Chapter headings: page break before, ample space above, no font sizes that fight device scaling
- `em`/`rem` throughout, no fixed pixels

Ship `epub.css` as an editable file in Application Support with a **Reveal stylesheet** command. It will need tuning.

Validate with `epubcheck` when available and surface results — KDP rejects on errors that are trivial to fix beforehand.

### 9.4 Print PDF target

```
pandoc Build/assembled.md --from=markdown+smart --to=typst -o Build/body.typ
typst compile Build/main.typ "The Last Shift - interior.pdf"
```

`main.typ` generated from a template, parameterized by `project.print`.

| Concern | Specification |
|---|---|
| Trim sizes | 5×8, 5.25×8, 5.5×8.5, 6×9 |
| Margins | Mirrored. Outside/top/bottom 0.625″ |
| Gutter | By page count: 0.375″ (≤150), 0.5″ (151–300), 0.625″ (301–500), 0.75″ (501–700) |
| Bleed | None for interior |
| Body | Serif, 11–11.5 pt, leading 1.3–1.4 |
| Paragraphs | First after heading/break flush; others indented 1.2 em; no inter-paragraph space |
| Chapter openers | Start on recto (configurable), drop ~1/3 page, drop folio |
| Running heads | Verso author, recto title. Small caps |
| Page numbers | Bottom center or outer. Front matter roman or unnumbered; body starts at arabic 1 |
| Widows/orphans | Suppressed |
| Scene break | Centered ornament; at a page break, substitute blank line plus indent suppression so the break isn't lost |

Gutter depends on final page count, which depends on layout — so compile once, read the page count, and recompile if it crosses a threshold. Two passes, automatic, invisible to the user.

### 9.5 DOCX fallback

```
pandoc Build/assembled.md --from=markdown+smart --to=docx \
  --reference-doc=reference.docx -o manuscript.docx
```

Ship a `reference.docx` with sane Normal and Heading 1 styles. For sending to an editor, and as an escape hatch when print layout needs manual work.

### 9.6 Compile sheet

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

## 10. Settings

| Pane | Contents |
|---|---|
| General | Projects location, default author name, reopen last project on launch |
| Editor | Font, size, line height, measured width, theme, typewriter scrolling, focus mode |
| Sync | GitHub account status, **Test Connection**, token management, push/fetch intervals, per-project remote URL, **Disconnect from GitHub** |
| Backup | Box backup location, mirror on/off, bundle frequency, retention count, last-run status, **Back Up Now**, **Restore from Bundle** |
| Versioning | Autosave interval, autocommit debounce, repo size (`git count-objects -vH`), **Run Maintenance** (`git gc`) |
| Tools | Resolved paths for git, pandoc, typst, epubcheck — status indicator and override field each |

---

## 11. Build phases

**M0 — Skeleton (usable: browse)**
Create/open project folder. Binder tree from disk. Read-only scene display. `project.json` read/write.

**M1 — Editing (usable: write a book)**
`NSTextView` wrapper, autosave with atomic writes, no hard wrapping, word counts, create/rename/delete/reorder with prefix re-sequencing, measured column, typewriter scrolling, ⌘I/⌘B.

**M2 — Local git (usable: safely)**
`GitService`, repo init, commit triggers, log, diff, History panel, restore. No remote yet. **This milestone alone makes the app safe to write in.**

**M3 — GitHub sync (usable: on two machines)**
Keychain credentials, GitHub API repo creation, clone existing, fetch/merge/push loop, sync status control, conflict detection and the per-file resolution sheet, concurrent-editing warning, FSEvents reload rules.

**M4 — Backup**
Box working-tree mirror, git bundle scheduling and retention, restore-from-bundle, backup status.

**M5 — Metadata & matter**
Project metadata editor, front/back matter generation, regenerate command, targets panel.

**M6 — EPUB export**
Assembler, pandoc invocation, `meta.yaml`, `epub.css`, compile sheet, epubcheck.

**M7 — Print export**
Typst template, trim sizes, mirrored margins, two-pass gutter, running heads, chapter openers, DOCX fallback.

**M8 — Polish**
Project-wide find & replace, focus mode, composition mode, settings panes, error-handling audit, onboarding.

---

## 12. Failure modes to handle explicitly

### 12.1 Working copy placed in a sync folder

The one failure that can silently destroy a repository. A `.git` directory inside Box, Dropbox, or iCloud Drive will eventually corrupt — thousands of small mutating files, no atomic directory semantics, placeholder eviction, and conflict copies written *into* the object store.

**Hard-block it.** On project create or open, resolve the real path and refuse any location under `~/Library/CloudStorage/`, `~/Dropbox`, `~/Google Drive`, `~/OneDrive`, or `~/Library/Mobile Documents/`. Explain why in one sentence and offer to relocate. Do not make this a dismissible warning.

### 12.2 Everything else

1. **Project folder moved or renamed while open** — FSEvents reports it. Halt writes, prompt to re-locate. Never write to a stale path.
2. **Push rejected (non-fast-forward)** — fetch, integrate per §5.6, retry once. If it fails again, surface it rather than looping.
3. **Merge conflict** — §5.7.
4. **Token expired or revoked** — detect the auth failure specifically (not as generic network failure), set status to `Not synced`, prompt to re-authenticate. Never lose work over it.
5. **Offline for days** — commits queue locally and push when connectivity returns. Show pending count. This is a normal state, not an error.
6. **Repo grows large from cover images** — a few MB of JPEG is fine uncommitted-repeatedly. If `Resources/` exceeds ~50 MB, suggest Git LFS in Settings, but don't redrafter it for v1.
7. **Two app instances open the same project** — check for an existing window bound to that path before opening.
8. **Non-UTF8 or BOM-prefixed files** — normalize on read, always write UTF-8 without BOM.
9. **Illegal filename characters** (`: / \ ? * " < > |`) — sanitize on rename.
10. **Very long scene (>20k words)** — must still perform. Test with a pathological file.
11. **git unavailable** — snapshot fallback (§6.2), persistent remediation banner.
12. **pandoc/typst missing or failing** — surface stderr verbatim, keep `Build/assembled.md` so the user can compile by hand.
13. **Disk full mid-save** — atomic write-and-rename (§6.5) makes this survivable.

---

## 13. Testing checklist

- Reorder 40 scenes across 12 chapters; confirm prefixes stay dense and `git log --follow` still tracks moved files.
- Write on machine A, close, open on machine B — confirm a clean fast-forward with no user-visible friction.
- Force divergence: edit *different* paragraphs of the same scene on both machines while offline, reconnect, confirm a clean automatic merge with no prompt.
- Force a true conflict: edit the *same* paragraph on both machines while offline, reconnect, confirm the conflict sheet and all three resolutions, especially Keep Both.
- Attempt to create a project inside Box Drive; confirm it is refused.
- Kill the app mid-typing (`kill -9`); confirm no truncated files and at most 2 s of lost work.
- Revoke the GitHub token mid-session; confirm writing continues uninterrupted and status reflects reality.
- Delete the local project entirely; clone from GitHub; confirm a byte-identical working tree.
- Restore from a Box bundle with no network; confirm full history recovery.
- Compile a 45k-word manuscript to EPUB; validate with epubcheck; open in Kindle Previewer.
- Compile to print PDF at 5×8; verify mirrored margins, correct gutter, recto chapter openers, running heads, no widows.

---

## 14. Deferred (post-v1)

Three-way merge editor with per-hunk resolution; compile presets saved per project; multiple manuscripts in one repo (for series); word-count history chart sourced from git log; scene-level time tracking; GitHub Releases as export archive; self-hosted or NAS remote as a first-class alternative to GitHub; iCloud/Dropbox support.

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
| Bundle everything | `git bundle create <file>.bundle --all` |
| Restore from bundle | `git clone <file>.bundle <dir>` |
| Repo size | `git count-objects -vH` |
| Maintenance | `git gc --auto` |

Use `%x1f` (unit separator) as the log field delimiter — commit subjects can contain nearly anything else.

Always pass `GIT_TERMINAL_PROMPT=0` in the subprocess environment. A git operation must never hang waiting on an invisible credential prompt.

## Appendix B — word counting

Count the markdown source with these removed: YAML front matter, `#` markers, `*`/`**` emphasis markers, scene separator lines, HTML comments. Split on whitespace; hyphenated compounds count as one; exclude standalone punctuation tokens.

Compute per-scene on save (debounced), cache in memory, aggregate upward for chapter and project totals. Never recompute the project on every keystroke.
