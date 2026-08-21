# Handoff: Drafter Redesign (macOS writing app)

## Overview
A full UI/UX redesign of Drafter, a Scrivener-style writing app: a three-pane main window (binder / editor / inspector), plus every supporting sheet — new/existing project, project settings, compile, version history & diff, Git conflict resolution, local file version control, and GitHub account settings — restyled on the **Nocturne** design system.

## About the Design Files
The files in this bundle are **design references built in HTML** (self-contained "Design Component" files) — they show intended look, layout and behavior, not production code to copy directly. The task is to **recreate these designs in Drafter's actual codebase/framework** (SwiftUI, Electron/React, or whatever it's built in), using that codebase's existing patterns, not by embedding this HTML.

## Fidelity
**High-fidelity.** Colors, type, spacing and component styling are final, taken directly from the bound Nocturne design system (see `design-system/nocturne/`). Recreate pixel-perfectly using the app's real UI framework, sourcing exact values from `design-system/nocturne/styles.css`.

## Files in this bundle
- `Drafter - Interactive Prototype.dc.html` — **primary reference.** The full app, wired up: binder expand/collapse, drag-to-reorder chapters/scenes, scene selection with real content, all toolbar buttons opening their sheets, New Chapter/Scene/Rename flows, Git-conflict compare/keep, version-control picker, compile target switch, settings tabs. Open this file in a browser and click through it — it's the most reliable spec for exact behavior.
- `Drafter - Main Window.dc.html` — three main-window layout directions explored; **1a (Classic three-pane)** is the one selected and carried into the interactive prototype. 1b/1c are alternates, not selected — ignore for build unless asked.
- `Drafter - Sheets & Settings.dc.html` — all modal sheets and settings tabs as static, labeled reference cards, including: New Project (both variants explored — **2b's card-style version-control picker was NOT selected; the prototype uses 2a-style radio buttons**, see prototype for ground truth), Add Existing Project, Project Settings (all 6 tabs: Book, Series, Publishing, Target, Compile, Print), Compile (2 variants explored, prototype uses the simpler EPUB/Print/DOCX segmented version), History & diff, Git conflict resolution, Local File Version Control, GitHub settings (disconnected + connected states), New Chapter/Rename prompt, empty states (no project open, empty binder), a compiling-progress banner, and a documented interaction-states reference (button/field/row default·hover·focus·disabled).
- `design-system/nocturne/` — the full Nocturne design system: `styles.css` (all tokens — colors, type, spacing, radii, shadows), `readme.md` (usage guide), `_ds_bundle.js` (reference component implementations, e.g. `.btn`, `.field`, `.tag`, `.dialog` — read for markup patterns, don't ship this JS).

## Screens / Views

### Main Window (three-pane)
- **Layout**: 1180×740 window. Titlebar 38px (macOS traffic-light dots). Body is a horizontal flex: binder (230px, fixed, scrollable) | editor (flex:1, min-width:0) | inspector (260px, fixed, collapsible via toolbar icon button, scrollable).
- **Binder**: collapsible sections (Manuscript, Front Matter, Back Matter), each with an 8px chevron that rotates -90° when collapsed. Manuscript section contains chapters (collapsible, each with a 10px chevron, drag handle for reordering, inline rename pencil icon revealed on hover) and scenes nested under each chapter (draggable between chapters, rename pencil, word count on the right in `--color-neutral-500`, 10.5px). Selected scene/front/back-matter row gets `background: var(--color-accent-800)`, text `var(--color-text)`. "+ Chapter" button sits directly under the last chapter's scenes, ghost button, 24px tall. Each chapter has a "+ Scene" text affordance under its scene list.
- **Editor toolbar** (44px): "Saved" + "·" + a `tag-accent` "Synced" pill, then right-aligned: Typewriter toggle (ghost, shows accent border+text when active), New Project…, Add Existing…, Version Control… (secondary), Project Settings… (secondary), Compile… (primary), inspector-toggle icon button.
- **Sync-conflict banner**: full-width row below the toolbar, background `color-mix(in oklch, var(--color-accent-2-700) 45%, var(--color-neutral-900))`, warning icon, message text, and Compare / Keep This One / Delete actions. Dismissible.
- **Editor body**: max-width 640px, centered. Breadcrumb (11px uppercase, `--color-accent-300`), title (22px heading font), italic synopsis (scenes only, 12.5px, `--color-neutral-400`), body paragraphs (15px/1.75, `--color-neutral-100`).
- **Inspector**: Targets block (word count, progress bar against goal, per-chapter breakdown) over a divider, then History block (list of named saves, each opens the diff modal).

### Modals (all via `.modal-backdrop` + `.sheet`, see Interactive Prototype for exact markup)
Every sheet: 12px radius, `--shadow-lg`, `1px solid var(--color-neutral-700)` border, header row with title + close (×) icon button, scrollable body with 18/20px padding and 14px gap between fields, footer row with right-aligned Cancel (ghost) + primary action.

- **New Project** (460px): Title/Author text fields, Save Location (path + Choose… button), Version Control as two clickable cards (Git+GitHub vs Local Files+Cloud) — selected card gets `border:1px solid var(--color-accent)`, `background:var(--color-accent-900)`.
- **Add Existing Project** (420×380): scrollable list of GitHub repos, each row name + `owner/repo` in `--color-neutral-500`, click to select and close.
- **Version Control** (420px, local-files mode): read-only key/value rows (Mode, Sync provider, Last Snapshot, Snapshots Kept, History Size) + footer actions Open History in Finder / Snapshot Now / Done.
- **Compile** (520×600): 3-way segmented target picker (EPUB / Print PDF / DOCX) as bordered cards, not native radios — active gets accent border+bg. Output location row. Front/Back matter checkboxes. Print target additionally reveals Trim Size swatches + Body Font/Point Size selects. Word-count estimate row pinned at the bottom of the body.
- **Project Settings** (520×560, 6 tabs: Book, Series, Publishing, Target, Compile, Print — tab row directly under the header, `2px solid var(--color-accent)` underline on the active tab): field sets per tab are fully specified in `Drafter - Sheets & Settings.dc.html` 3a–3e and in the prototype's settings body. Target tab includes a 3-way Drafting/Revising/Complete segmented status control.
- **History & diff** (two-pane: 230px commit list + 640px diff): commit rows show subject + relative time + word delta; diff pane is a two-column table, deletions struck through in `--color-neutral-600`, insertions colored `--color-accent-200`.
- **Git conflict resolution** (560×420): one row per conflicted file, showing "Mine" vs "Theirs" provenance, Compare/Keep Mine/Keep Theirs/Keep Both actions; resolved rows collapse to 55% opacity with a checkmark. Footer "Done" is disabled until all files are resolved.
- **GitHub Settings**: disconnected state shows a masked Personal Access Token field + Test Connection button; connected state (3i) shows status "● Connected as tfleet" in `--color-accent-200`, linked repo, last sync time, and a Disconnect ghost button.
- **New Chapter / New Scene / Rename**: single-field prompt sheet (360px), autofocus, Cancel/Create(or Rename) footer.

## Empty & secondary states (see Sheets & Settings 3f–3i)
- **No project open**: centered welcome content in the window body — title, subtext, Add Existing…/New Project… buttons, a "Recent" list below a divider.
- **Empty binder** (brand-new project): Manuscript section shows only a "+ Chapter" button, no chapters; editor pane shows a centered "This manuscript doesn't have any chapters yet." message + primary "+ Chapter" button; inspector pane renders empty.
- **Compiling banner**: replaces/sits below the toolbar — spinner icon, "Compiling to EPUB…" label, progress bar, Cancel button.
- **GitHub connected**: see above.

## Interactions & Behavior
- Binder sections and chapters toggle expand/collapse on click; chevron rotates.
- Scenes and chapters are drag-and-drop reorderable (scene → any chapter, chapter → chapter for reordering).
- Clicking a scene/front/back-matter row loads its content into the editor and updates the breadcrumb/title/synopsis.
- Toolbar buttons open their respective sheet as a modal (backdrop click or × closes without saving, except where noted).
- Typewriter toggle is a local boolean, changes only the button's own visual state (accent border + text) in this prototype — actual centering/scroll behavior is an implementation detail for the dev to define.
- Compile target and Settings tab selection are simple local state swaps within their modals.
- New Chapter/New Scene/Rename share one prompt-sheet pattern; submit validates non-empty text.
- Toast confirmations (e.g. "Project created", "Compiled to ~/Desktop/…") appear top-center, auto-dismiss after ~2.5s.
- **Interaction states** (button/field/binder-row/tab — default, hover, focus-visible, disabled, selected/active) are documented explicitly in Sheets & Settings 3j–3k. These follow Nocturne's systemic states (hover = accent-tinted background per variant, focus = 2px accent outline offset 2px, disabled = 45% opacity) — don't hand-roll custom per-screen hover/focus styling, use the design system's existing state treatment.

## State Management
Suggested state shape (already modeled in the prototype's logic class):
- `selectedId` — currently open scene/front/back-matter item
- `expandedSections` / `expandedChapters` — binder collapse state
- `chapters[]` (each with nested `scenes[]`), `frontMatter[]`, `backMatter[]` — the manuscript tree
- `modal` — `{ type, ...extra }` or `null`, drives which sheet is open
- `isTypewriter`, `inspectorOpen`, `bannerDismissed` — editor UI toggles
- `versionControlChoice`, `compileTarget`, `settingsTab` — modal-local selections
- `toast` — transient confirmation message

## Design Tokens
Full token set lives in `design-system/nocturne/styles.css` — source from there, don't hardcode. Key values:
- Ground: `--color-bg` `#161826`; text `--color-text` `#e9e9ed`; accent `#9184d9` (single-accent mono scheme, 100–900 tonal ramps for both accent roles)
- Fonts: Inter for both `--font-heading` and `--font-body`
- Radius: 8px base scale (`--radius-sm/md/lg`)
- Density: 0.7× spacing scale — this UI is intentionally compact
- Shadows: `--shadow-sm/md/lg`, tuned for the dark ground — don't add extra box-shadows
- Buttons are outlined, never solid-filled, per Nocturne's direction

## Assets
No custom imagery. Icons are inline Phosphor SVGs (see any `<svg>` in the prototype — path data is copy-pasteable, or re-source the same icons from https://phosphoricons.com by name if the codebase already vendors Phosphor).

## Open items not covered by this handoff
- Real content loading/saving, file system integration, actual Git/GitHub operations, actual EPUB/PDF/DOCX compilation — all mocked with static sample data in the prototype.
- Responsive/window-resize behavior below the 1180×740 baseline (the prototype scales the whole window down to fit small viewports; decide whether the real app should do the same or reflow panes).
