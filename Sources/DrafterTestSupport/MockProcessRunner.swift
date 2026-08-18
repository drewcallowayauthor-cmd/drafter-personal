import DrafterCore
import Foundation

/// A scripted `ProcessRunning` fake. Register results for a given executable name in the
/// order they should be returned — each call to `run` for that executable pops the next
/// one off the queue. Once the queue is drained, the last scripted result is returned
/// again for any further calls, so a single `script(...)` call still behaves as "always
/// return this" for tests that only care about one invocation.
public actor MockProcessRunner: ProcessRunning {
    public struct Invocation: Sendable, Equatable {
        public let executableURL: URL
        public let arguments: [String]
        public let currentDirectoryURL: URL?
        public let environment: [String: String]?
    }

    private var queues: [String: [Result<ProcessResult, Error>]] = [:]
    private var _invocations: [Invocation] = []

    public init() {}

    public var invocations: [Invocation] { _invocations }

    public func script(_ result: ProcessResult, forExecutableNamed name: String) {
        queues[name, default: []].append(.success(result))
    }

    public func script(throwing error: Error, forExecutableNamed name: String) {
        queues[name, default: []].append(.failure(error))
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        _invocations.append(
            Invocation(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment
            )
        )

        let name = executableURL.lastPathComponent
        let outcome: Result<ProcessResult, Error>
        if var queue = queues[name], !queue.isEmpty {
            outcome = queue.removeFirst()
            queues[name] = queue.isEmpty ? [outcome] : queue
        } else {
            outcome = .success(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        }

        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
