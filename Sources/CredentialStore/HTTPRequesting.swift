import Foundation

/// Abstraction over performing a `URLRequest`. `GitHubAPIClient` depends on this rather
/// than `URLSession` directly, so its request-building and response-parsing logic can be
/// unit tested against a fake without touching the network — same pattern as
/// `ProcessRunning` for subprocesses.
public protocol HTTPRequesting: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed implementation used at runtime.
public struct LiveHTTPRequester: HTTPRequesting {
    public init() {}

    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}
