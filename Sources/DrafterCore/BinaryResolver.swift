import Foundation

/// Locates an external binary (`pandoc`, `typst`, `epubcheck`) on disk. An explicit
/// Settings override always wins (a deliberate user choice shouldn't be silently
/// shadowed by a bundled copy); after that, the app's own bundled binary if it has one
/// (`pandoc`/`typst` — see `BundledBinaries`, macOS arm64 only), then a fixed list of
/// common install locations (since these tools are rarely installed via a package
/// manager that puts them on a *login shell's* PATH in a way `Process` inherits), then
/// the process's actual `PATH` environment variable.
public enum BinaryResolver {
    public static let defaultCandidateDirectories = [
        "~/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]

    public static func resolve(
        name: String,
        override: URL? = nil,
        bundled: URL? = nil,
        candidateDirectories: [String] = defaultCandidateDirectories,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override, fileManager.isExecutableFile(atPath: override.path) {
            return override
        }

        if let bundled, fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for directory in candidateDirectories {
            let expanded = (directory as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expanded).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }
}
