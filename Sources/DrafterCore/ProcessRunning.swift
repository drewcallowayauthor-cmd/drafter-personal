import Foundation

/// The result of running a subprocess to completion.
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Abstraction over launching a subprocess (`git`, `pandoc`, `typst`, …).
///
/// Every service that shells out depends on this protocol rather than `Foundation.Process`
/// directly, so its command-building and result-handling logic can be unit tested against
/// a fake without touching a real binary. Integration tests exercise the live implementation
/// against real binaries in a scratch directory.
public protocol ProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

/// `Foundation.Process`-backed implementation used at runtime.
public struct LiveProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            if let currentDirectoryURL {
                process.currentDirectoryURL = currentDirectoryURL
            }
            if let environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
                    standardError: String(data: stderrData, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
