import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import CredentialStore

@Suite("GitHubAPIClient")
struct GitHubAPIClientTests {
    @Test("createRepository decodes the created repo and sends a private repo request")
    func createRepositoryDecodesResponse() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 201, jsonObject: [
            "name": "last-call",
            "full_name": "drew/last-call",
            "clone_url": "https://github.com/drew/last-call.git",
            "html_url": "https://github.com/drew/last-call",
            "private": true
        ])
        let client = GitHubAPIClient(requester: requester)

        let repo = try await client.createRepository(name: "last-call", token: "ghp_abc")

        #expect(repo.name == "last-call")
        #expect(repo.fullName == "drew/last-call")
        #expect(repo.cloneURL == URL(string: "https://github.com/drew/last-call.git"))
        #expect(repo.isPrivate == true)

        let invocations = await requester.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0].httpMethod == "POST")
        #expect(invocations[0].value(forHTTPHeaderField: "Authorization") == "Bearer ghp_abc")
        let body = try #require(invocations[0].httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "last-call")
        #expect(json["private"] as? Bool == true)
    }

    @Test("createRepository with a taken name surfaces githubAPIError, not a generic failure")
    func createRepositoryNameTakenSurfacesAPIError() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 422, jsonObject: ["message": "name already exists on this account"])
        let client = GitHubAPIClient(requester: requester)

        do {
            _ = try await client.createRepository(name: "taken", token: "ghp_abc")
            Issue.record("expected createRepository to throw")
        } catch DrafterError.githubAPIError(let statusCode, let message) {
            #expect(statusCode == 422)
            #expect(message == "name already exists on this account")
        }
    }

    @Test("a 401 response maps to authenticationFailed")
    func unauthorizedMapsToAuthenticationFailed() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 401, jsonObject: ["message": "Bad credentials"])
        let client = GitHubAPIClient(requester: requester)

        do {
            _ = try await client.currentUser(token: "bad-token")
            Issue.record("expected currentUser to throw")
        } catch let error as DrafterError {
            #expect(error == .authenticationFailed)
        }
    }

    @Test("a transport error maps to offline")
    func transportErrorMapsToOffline() async throws {
        let requester = MockHTTPRequester()
        await requester.script(throwing: URLError(.notConnectedToInternet))
        let client = GitHubAPIClient(requester: requester)

        do {
            _ = try await client.currentUser(token: "ghp_abc")
            Issue.record("expected currentUser to throw")
        } catch let error as DrafterError {
            #expect(error == .offline)
        }
    }

    @Test("a non-connectivity transport error surfaces distinctly rather than collapsing to offline")
    func nonConnectivityTransportErrorDoesNotMapToOffline() async throws {
        let requester = MockHTTPRequester()
        await requester.script(throwing: URLError(.badServerResponse))
        let client = GitHubAPIClient(requester: requester)

        do {
            _ = try await client.currentUser(token: "ghp_abc")
            Issue.record("expected currentUser to throw")
        } catch let error as DrafterError {
            #expect(error != .offline)
            if case .githubAPIError = error {
                // expected: a real, distinct failure rather than a silently-retried offline state
            } else {
                Issue.record("expected .githubAPIError, got \(error)")
            }
        }
    }

    @Test("listRepositories decodes an array and requests the owner's repos")
    func listRepositoriesDecodesArray() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 200, jsonObject: [
            [
                "name": "book-one",
                "full_name": "drew/book-one",
                "clone_url": "https://github.com/drew/book-one.git",
                "html_url": "https://github.com/drew/book-one",
                "private": true
            ]
        ])
        let client = GitHubAPIClient(requester: requester)

        let repos = try await client.listRepositories(token: "ghp_abc")

        #expect(repos.count == 1)
        #expect(repos[0].name == "book-one")

        let invocations = await requester.invocations
        #expect(invocations[0].httpMethod == "GET")
        #expect(invocations[0].url?.absoluteString.contains("affiliation=owner") == true)
    }

    @Test("currentUser decodes login and email")
    func currentUserDecodesLoginAndEmail() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 200, jsonObject: ["login": "drew", "email": "drew@example.com"])
        let client = GitHubAPIClient(requester: requester)

        let user = try await client.currentUser(token: "ghp_abc")

        #expect(user.login == "drew")
        #expect(user.email == "drew@example.com")
    }

    @Test("currentUser tolerates a null email")
    func currentUserToleratesNullEmail() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 200, jsonObject: ["login": "drew", "email": NSNull()])
        let client = GitHubAPIClient(requester: requester)

        let user = try await client.currentUser(token: "ghp_abc")

        #expect(user.login == "drew")
        #expect(user.email == nil)
    }

    @Test("every request carries the required GitHub API headers")
    func requestsCarryRequiredHeaders() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 200, jsonObject: ["login": "drew", "email": NSNull()])
        let client = GitHubAPIClient(requester: requester)

        _ = try await client.currentUser(token: "ghp_abc")

        let request = try #require(await requester.invocations.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Drafter")
    }

    @Test("containsFile returns true on 200")
    func containsFileReturnsTrueOn200() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 200, jsonObject: ["name": "project.json"])
        let client = GitHubAPIClient(requester: requester)

        let exists = try await client.containsFile(fullName: "drew/last-call", path: "project.json", token: "ghp_abc")

        #expect(exists == true)
        let invocations = await requester.invocations
        #expect(invocations.first?.url?.path == "/repos/drew/last-call/contents/project.json")
    }

    @Test("containsFile returns false on 404 rather than throwing")
    func containsFileReturnsFalseOn404() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 404, jsonObject: ["message": "Not Found"])
        let client = GitHubAPIClient(requester: requester)

        let exists = try await client.containsFile(fullName: "drew/other-repo", path: "project.json", token: "ghp_abc")

        #expect(exists == false)
    }

    @Test("containsFile still surfaces authenticationFailed on 401")
    func containsFileSurfacesAuthFailureOn401() async throws {
        let requester = MockHTTPRequester()
        await requester.script(statusCode: 401, jsonObject: ["message": "Bad credentials"])
        let client = GitHubAPIClient(requester: requester)

        do {
            _ = try await client.containsFile(fullName: "drew/last-call", path: "project.json", token: "bad")
            Issue.record("expected containsFile to throw")
        } catch let error as DrafterError {
            #expect(error == .authenticationFailed)
        }
    }
}
