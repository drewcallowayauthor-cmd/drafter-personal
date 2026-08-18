import DrafterCore
import Foundation

/// A scripted `ProcessRunning` fake. Register a result (or error) for a given executable
/// name; `run` records every invocation so tests can assert on the exact command built.
public actor MockProcessRunner: ProcessRunning {
    public struct Invocation: Sendable, Equatable {
        public let executableURL: URL
        public let arguments: [String]
        public let currentDirectoryURL: URL?
        public let environment: [String: String]?
    }

    private var scriptedResults: [String: Result<ProcessResult, Error>] = [:]
    private var _invocations: [Invocation] = []

    public init() {}

    public var invocations: [Invocation] { _invocations }

    public func script(_ result: ProcessResult, forExecutableNamed name: String) {
        scriptedResults[name] = .success(result)
    }

    public func script(throwing error: Error, forExecutableNamed name: String) {
        scriptedResults[name] = .failure(error)
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

        switch scriptedResults[executableURL.lastPathComponent] {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        case nil:
            return ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
    }
}
