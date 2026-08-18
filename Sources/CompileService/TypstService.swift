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

    /// `typst compile <input> <output>` (§9.4).
    public func compile(inputPath: String, outputPath: String, in workingDirectory: URL) async throws -> ProcessResult {
        try await run(arguments: ["compile", inputPath, outputPath], in: workingDirectory)
    }
}
