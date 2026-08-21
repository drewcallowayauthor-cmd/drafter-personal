import DrafterCore
import Foundation
import Observation

/// Backs the Tools pane (§12): resolves git/pandoc/typst/epubcheck each time an override
/// changes, so the pane always shows where the binary Drafter will actually invoke lives.
@MainActor
@Observable
final class ToolsSettingsViewModel {
    struct ToolStatus: Identifiable {
        let id: String
        let displayName: String
        let resolvedPath: String?
    }

    private(set) var statuses: [ToolStatus] = []

    func refresh() {
        let prefs = AppPreferences.shared
        statuses = [
            resolve(id: "git", displayName: "git", override: prefs.gitPathOverride),
            resolve(id: "pandoc", displayName: "pandoc", override: prefs.pandocPathOverride),
            resolve(id: "typst", displayName: "typst", override: prefs.typstPathOverride),
            resolve(id: "epubcheck", displayName: "epubcheck", override: prefs.epubcheckPathOverride)
        ]
    }

    private func resolve(id: String, displayName: String, override: String?) -> ToolStatus {
        let overrideURL = override.map { URL(fileURLWithPath: $0) }
        // `git`'s own fallback (`GitService`'s default `gitExecutableURL`) is the
        // system binary at `/usr/bin/git`, outside `BinaryResolver`'s usual candidate
        // list — added here so this pane doesn't show "Not found" for the common case
        // of relying on Xcode CLT's git with no override set.
        let candidateDirectories = id == "git"
            ? BinaryResolver.defaultCandidateDirectories + ["/usr/bin"]
            : BinaryResolver.defaultCandidateDirectories
        let resolved = BinaryResolver.resolve(name: id, override: overrideURL, candidateDirectories: candidateDirectories)
        return ToolStatus(id: id, displayName: displayName, resolvedPath: resolved?.path)
    }
}
