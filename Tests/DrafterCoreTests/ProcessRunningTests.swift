import Foundation
import Testing
@testable import DrafterCore

@Suite("LiveProcessRunner")
struct ProcessRunningTests {
    /// A subprocess writing more than the pipe's kernel buffer (~64KB) before exiting
    /// used to deadlock: nothing drained the pipe until `terminationHandler` fired, and
    /// `terminationHandler` couldn't fire because the child was blocked on `write()`.
    /// This exercises exactly that shape with real stdout+stderr volume and a
    /// wall-clock timeout, so a regression here hangs the test rather than passing.
    @Test("drains large stdout/stderr without deadlocking")
    func drainsLargeOutputWithoutDeadlocking() async throws {
        let runner = LiveProcessRunner()
        let byteCount = 300_000

        let result = try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await runner.run(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "yes | head -c \(byteCount) >&1; yes | head -c \(byteCount) >&2"],
                    currentDirectoryURL: nil,
                    environment: nil
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TimeoutError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        #expect(result.succeeded)
        #expect(result.standardOutput.utf8.count == byteCount)
        #expect(result.standardError.utf8.count == byteCount)
    }

    private struct TimeoutError: Error {}
}
