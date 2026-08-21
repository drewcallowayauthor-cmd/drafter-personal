# Bundled binaries

Drafter ships `pandoc` and `typst` inside the app so exporting works with no separate
install step. Both are invoked as ordinary subprocesses (`ProcessRunning`) — never
linked into the app — so bundling them doesn't affect Drafter's own license.

## Compatibility: Apple Silicon (arm64) only

The binaries in this directory are macOS arm64 builds. On an Intel Mac (or an arm64 Mac
running under Rosetta with an x86_64-only process), they simply won't execute, and
`BinaryResolver` falls back to searching `~/.local/bin`, `/opt/homebrew/bin`,
`/usr/local/bin`, and `PATH` — the same behavior as before bundling existed. An Intel
Mac user just needs `pandoc`/`typst` installed via Homebrew (or any other means) for
export to work.

## Licenses

- **pandoc** — GPL-2.0-or-later. License text: `pandoc-COPYING.txt` (this directory).
  Corresponding source: the exact release this binary was built from,
  <https://github.com/jgm/pandoc/releases> — currently pandoc 3.10.2.
- **typst** — Apache-2.0. License text: `typst-LICENSE.txt` (this directory).
  Source: <https://github.com/typst/typst> — currently typst 0.15.1.

## Updating

Replace the binary, re-run `pandoc --version` / `typst --version` to confirm the new
version, and update the version numbers above.
