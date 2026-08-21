import CredentialStore
import Foundation

/// A scripted `HTTPRequesting` fake. Register responses in the order they should be
/// returned — each call to `perform` pops the next one off the queue. Once drained, the
/// last scripted response is returned again, so a single `script(...)` call still behaves
/// as "always return this" for tests that only care about one invocation. Mirrors
/// `MockProcessRunner`'s conventions.
public actor MockHTTPRequester: HTTPRequesting {
    private var queue: [Result<(Data, HTTPURLResponse), Error>] = []
    private var _invocations: [URLRequest] = []

    public init() {}

    public var invocations: [URLRequest] { _invocations }

    public func script(statusCode: Int, jsonObject: Any, url: URL = URL(string: "https://api.github.com")!) {
        let data = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        queue.append(.success((data, response)))
    }

    public func script(statusCode: Int, data: Data, url: URL = URL(string: "https://api.github.com")!) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        queue.append(.success((data, response)))
    }

    public func script(throwing error: Error) {
        queue.append(.failure(error))
    }

    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        _invocations.append(request)

        let outcome: Result<(Data, HTTPURLResponse), Error>
        if !queue.isEmpty {
            outcome = queue.removeFirst()
            if queue.isEmpty { queue = [outcome] }
        } else {
            outcome = .success((Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }

        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
