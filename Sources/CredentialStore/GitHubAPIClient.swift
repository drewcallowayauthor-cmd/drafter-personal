import DrafterCore
import Foundation

/// A repo as returned by the GitHub REST API — just the fields §5.2/§5.9 need: where to
/// push (`cloneURL`) and where to send a human (`htmlURL`).
public struct GitHubRepository: Sendable, Equatable, Decodable, Identifiable {
    public let name: String
    public let fullName: String
    public let cloneURL: URL
    public let htmlURL: URL
    public let isPrivate: Bool

    public var id: String { fullName }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case cloneURL = "clone_url"
        case htmlURL = "html_url"
        case isPrivate = "private"
    }
}

/// The authenticated user (§5.2 step 4: local `user.email` is set to the GitHub account
/// email). `email` is `nil` when the account has no public email and the token lacks the
/// scope to see the private one — callers fall back to the `login@users.noreply.github.com`
/// convention GitHub itself uses.
public struct GitHubUser: Sendable, Equatable, Decodable {
    public let login: String
    public let email: String?
}

/// Thin wrapper around the subset of the GitHub REST API §5.2/§5.3/§5.9 need: create a
/// private repo, list the account's repos, and identify the authenticated user. Every
/// call requires a token — v1 has no anonymous mode — and network/auth failures resolve
/// to `DrafterError` so the UI can react by category rather than parsing error strings.
public actor GitHubAPIClient {
    public static let defaultBaseURL = URL(string: "https://api.github.com")!
    private static let apiVersion = "2022-11-28"

    private let requester: HTTPRequesting
    private let baseURL: URL

    public init(requester: HTTPRequesting = LiveHTTPRequester(), baseURL: URL = GitHubAPIClient.defaultBaseURL) {
        self.requester = requester
        self.baseURL = baseURL
    }

    /// `POST /user/repos` (§5.2) — creates a private repo under the authenticated
    /// account. GitHub returns 422 when the name is already taken; that surfaces as
    /// `.githubAPIError` so the caller can fall back to the "Not synced" local-only path.
    public func createRepository(name: String, token: String) async throws -> GitHubRepository {
        var request = try makeRequest(path: "/user/repos", method: "POST", token: token)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "private": true])
        } catch {
            throw DrafterError.filesystem(underlying: String(describing: error))
        }
        return try await send(request)
    }

    /// `GET /user/repos` (§5.9) — repos owned by the authenticated account, newest
    /// first. Filtering to those with a `project.json` at root is a caller concern (it
    /// needs a second request per repo) — this just lists what's there.
    public func listRepositories(token: String) async throws -> [GitHubRepository] {
        let request = try makeRequest(
            path: "/user/repos?per_page=100&affiliation=owner&sort=created&direction=desc",
            method: "GET",
            token: token
        )
        return try await send(request)
    }

    /// `GET /user` — used to verify a token (§5.3's "never store a token that hasn't
    /// been verified") and to source the local git identity's email (§5.2 step 4).
    public func currentUser(token: String) async throws -> GitHubUser {
        let request = try makeRequest(path: "/user", method: "GET", token: token)
        return try await send(request)
    }

    /// `GET /repos/{full_name}/contents/{path}` — used by §5.9's repo picker to filter
    /// `listRepositories`' results down to ones that actually look like Drafter
    /// projects (contain a `project.json` at root), rather than every repo the account
    /// owns. A 404 means "no such file," not a failure — resolves to `false`, not a
    /// thrown error.
    public func containsFile(fullName: String, path: String, token: String) async throws -> Bool {
        let encodedFullName = fullName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fullName
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let request = try makeRequest(
            path: "/repos/\(encodedFullName)/contents/\(encodedPath)", method: "GET", token: token
        )
        let (data, statusCode) = try await performRequest(request)
        if statusCode == 404 { return false }
        try Self.throwIfError(statusCode: statusCode, data: data)
        return true
    }

    private func makeRequest(path: String, method: String, token: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw DrafterError.githubAPIError(statusCode: -1, message: "Couldn't build a request URL for \(path).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Drafter", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        do {
            let (data, response) = try await requester.perform(request)
            return (data, response.statusCode)
        } catch {
            // Only genuine connectivity failures read as `.offline` (§5.5's "queue and
            // retry, don't alarm the user"). Anything else — a malformed response, TLS
            // failure, etc. — is a real failure that would otherwise retry forever
            // while silently never succeeding, so it needs to surface distinctly.
            if let urlError = error as? URLError, Self.offlineURLErrorCodes.contains(urlError.code) {
                throw DrafterError.offline
            }
            DrafterLog.credential.error("GitHub request failed: \(error, privacy: .public)")
            throw DrafterError.githubAPIError(
                statusCode: -1, message: "Couldn't reach GitHub: \(error.localizedDescription)"
            )
        }
    }

    private static let offlineURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
    ]

    private static func throwIfError(statusCode: Int, data: Data) throws {
        guard (200...299).contains(statusCode) else {
            if statusCode == 401 || statusCode == 403 {
                throw DrafterError.authenticationFailed
            }
            throw DrafterError.githubAPIError(statusCode: statusCode, message: errorMessage(from: data))
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, statusCode) = try await performRequest(request)
        try Self.throwIfError(statusCode: statusCode, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            DrafterLog.credential.error("Failed to decode GitHub API response: \(error, privacy: .public)")
            throw DrafterError.githubAPIError(
                statusCode: statusCode, message: "GitHub returned an unexpected response."
            )
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String
        else {
            return "Unknown error"
        }
        return message
    }
}
