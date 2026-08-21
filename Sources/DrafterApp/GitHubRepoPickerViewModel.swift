import CredentialStore
import DrafterCore
import Observation

/// Backs §5.9's "Add Existing Project" picker: repos owned by the saved token's
/// account (`GitHubAPIClient.listRepositories` already scopes to `affiliation=owner`,
/// i.e. never someone else's repo the account merely collaborates on), filtered down
/// to the ones that actually look like Drafter projects — a `project.json` at root.
@MainActor
@Observable
final class GitHubRepoPickerViewModel {
    private(set) var repositories: [GitHubRepository] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let credentialStore: CredentialStore
    private let apiClient: GitHubAPIClient

    init(credentialStore: CredentialStore = CredentialStore(), apiClient: GitHubAPIClient = GitHubAPIClient()) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let token = try? await credentialStore.loadToken(), !token.isEmpty else {
            errorMessage = "Connect a GitHub account in Settings first."
            return
        }

        do {
            let owned = try await apiClient.listRepositories(token: token)
            var drafterRepositories: [GitHubRepository] = []
            for repository in owned {
                let looksLikeDrafterProject = (try? await apiClient.containsFile(
                    fullName: repository.fullName,
                    path: "project.json",
                    token: token
                )) == true
                if looksLikeDrafterProject {
                    drafterRepositories.append(repository)
                }
            }
            repositories = drafterRepositories
        } catch DrafterError.authenticationFailed {
            errorMessage = "Your saved token was rejected. Reconnect in Settings."
        } catch DrafterError.offline {
            errorMessage = "Couldn't reach GitHub. Check your connection and try again."
        } catch {
            errorMessage = "Couldn't load repositories: \(String(describing: error))"
        }
    }
}
