import DrafterCore
import Foundation

/// Subprocess wrapper around `typst` (§9.4), mirroring `PandocService`: never throws
/// on non-zero exit, since §9.6 wants raw stderr surfaced on failure rather than
/// swallowed.
public actor TypstService {
    private let processRunner: ProcessRunning
    private let typstExecutableURL: URL

    public init(processRunner: ProcessRunning, typstExecutableURL: URL) {
        self.processRunner = processRunner
        self.typstExecutableURL = typstExecutableURL
    }

    public func run(arguments: [String], in workingDirectory: URL) async throws -> ProcessResult {
        try await processRunner.run(
            executableURL: typstExecutableURL,
            arguments: arguments,
            currentDirectoryURL: workingDirectory,
            environment: nil
        )
    }

    /// `typst compile <input> <output>` (§9.4). `fontPaths` adds `--font-path`
    /// directories typst searches before falling back to system fonts — how a
    /// font bundled with the app (rather than installed on the Mac) gets found.
    public func compile(
        inputPath: String,
        outputPath: String,
        fontPaths: [String] = [],
        in workingDirectory: URL
    ) async throws -> ProcessResult {
        let fontArguments = fontPaths.flatMap { ["--font-path", $0] }
        return try await run(arguments: ["compile"] + fontArguments + [inputPath, outputPath], in: workingDirectory)
    }
}
