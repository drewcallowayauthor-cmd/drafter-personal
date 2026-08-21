import Foundation

/// Locates an external binary (`pandoc`, `typst`, `epubcheck`) on disk. §2.1's order is
/// bundled → user-configured path in Settings → PATH; bundling isn't built yet, so today
/// this covers the Settings-override and PATH-equivalent steps — an optional user-supplied
/// override, then a fixed list of common install locations (since these tools are rarely
/// installed via a package manager that puts them on a *login shell's* PATH in a way
/// `Process` inherits), then the process's actual `PATH` environment variable.
public enum BinaryResolver {
    public static let defaultCandidateDirectories = [
        "~/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]

    public static func resolve(
        name: String,
        override: URL? = nil,
        candidateDirectories: [String] = defaultCandidateDirectories,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override, fileManager.isExecutableFile(atPath: override.path) {
            return override
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
