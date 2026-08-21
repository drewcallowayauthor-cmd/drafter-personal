# Drafter

A macOS app for long-form fiction: chapter/scene binder, distraction-free editing,
version history (local git or plain-folder snapshots), and EPUB/print-PDF/DOCX export.

## Requirements

- **macOS on Apple Silicon (arm64).** Drafter bundles `pandoc` and `typst` for export,
  and those bundled binaries are arm64-only (see
  [`Sources/DrafterApp/Resources/Binaries/README.md`](Sources/DrafterApp/Resources/Binaries/README.md)).
  On an Intel Mac, exporting still works if you install `pandoc`/`typst` yourself (e.g.
  via Homebrew) — Drafter falls back to searching `PATH` and common install locations
  when the bundled binaries can't run.
- [Git LFS](https://git-lfs.com) to clone this repo — the bundled `pandoc`/`typst`
  binaries are stored via LFS, not as regular git blobs.

## Building

```
git lfs install   # once per machine
git clone <this repo>
swift build
swift test
```

## License

Drafter is licensed under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0). You're free to use, modify, and redistribute it — including commercially —
but any distributed copy (including a version offered over a network) must also make
its source available under AGPL-3.0.

## Third-party licenses

Drafter bundles two external tools, invoked as subprocesses rather than linked into the
app:

- **[pandoc](https://pandoc.org)** — GPL-2.0-or-later
- **[typst](https://typst.app)** — Apache-2.0

Full license texts and version/source pointers are in
[`Sources/DrafterApp/Resources/Binaries/`](Sources/DrafterApp/Resources/Binaries/).
