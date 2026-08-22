import Foundation

/// `pandoc` and `typst` shipped inside the app bundle so writing works without asking
/// the user to install anything first. Apple Silicon (arm64) only — see
/// `Resources/Binaries/README.md` for why, and for the Intel fallback (`BinaryResolver`
/// still searches PATH/common install locations if these don't resolve, e.g. running
/// under Rosetta or on an Intel Mac with pandoc/typst installed via Homebrew).
///
/// License note: pandoc is GPL-2.0-or-later, typst is Apache-2.0. Both are invoked here
/// as separate subprocesses (`ProcessRunning`), never linked into the app — see
/// `Resources/Binaries/` for each tool's license text and source pointer.
enum BundledBinaries {
    static var pandocURL: URL? {
        ResourceBundle.current.url(forResource: "pandoc", withExtension: nil, subdirectory: "Binaries")
    }

    static var typstURL: URL? {
        ResourceBundle.current.url(forResource: "typst", withExtension: nil, subdirectory: "Binaries")
    }
}
