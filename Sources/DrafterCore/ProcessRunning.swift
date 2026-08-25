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

            // A subprocess can write more than the pipe's kernel buffer (~64KB) before
            // exiting; if nothing drains the pipe until termination, the child blocks on
            // write() and never terminates, deadlocking the wait below. Draining
            // incrementally as data arrives avoids that.
            let stdoutBuffer = LockedData()
            let stderrBuffer = LockedData()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            process.terminationHandler = { process in
                // availableData returns empty Data at EOF, so a final drain here
                // (after the readabilityHandler has stopped firing) picks up any
                // remainder without racing the handler.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(data: stdoutBuffer.data, encoding: .utf8) ?? "",
                    standardError: String(data: stderrBuffer.data, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                // swiftlint:disable:next line_length
                DrafterLog.app.error("Failed to launch \(executableURL.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                continuation.resume(
                    throwing: DrafterError.processLaunchFailed(
                        name: executableURL.lastPathComponent,
                        underlying: String(describing: error)
                    )
                )
            }
        }
    }
}

/// A `Data` accumulator safe to append to from a pipe's `readabilityHandler` queue while
/// being read from the process's `terminationHandler` queue.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
