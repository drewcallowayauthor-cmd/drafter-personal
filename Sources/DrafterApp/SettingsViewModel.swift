import CredentialStore
import DrafterCore
import Foundation
import Observation

/// Backs the Sync pane of Settings (§10): verify-then-store a PAT (§5.3 — "never store
/// a token that hasn't been verified"), and disconnect.
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var connectedLogin: String?
    private(set) var statusMessage: String?
    private(set) var isTesting = false

    private let credentialStore: CredentialStore
    private let apiClient: GitHubAPIClient

    init(credentialStore: CredentialStore = CredentialStore(), apiClient: GitHubAPIClient = GitHubAPIClient()) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    /// Re-verifies whatever token is already saved, so "Connected as X" reflects
    /// reality rather than a stale save (§5.3's "Test Connection... reports the actual
    /// result" applies just as much on reopening Settings as it does to a fresh entry).
    func loadStatus() async {
        let token: String?
        do {
            token = try await credentialStore.loadToken()
        } catch {
            DrafterLog.credential.error("Failed to load the saved GitHub token: \(error, privacy: .public)")
            connectedLogin = nil
            return
        }
        guard let token else {
            connectedLogin = nil
            return
        }
        do {
            connectedLogin = try await apiClient.currentUser(token: token).login
        } catch {
            DrafterLog.credential.error("Failed to verify the saved GitHub token: \(error, privacy: .public)")
            connectedLogin = nil
        }
    }

    func testAndSave(token: String) async {
        guard !token.isEmpty else { return }
        statusMessage = nil
        isTesting = true
        defer { isTesting = false }
        do {
            let user = try await apiClient.currentUser(token: token)
            try await credentialStore.saveToken(token)
            connectedLogin = user.login
            statusMessage = "Connected as \(user.login)."
            NotificationCenter.default.post(name: .drafterCredentialsUpdated, object: nil)
        } catch DrafterError.authenticationFailed {
            statusMessage = "That token was rejected. Check it and try again."
        } catch DrafterError.offline {
            statusMessage = "Couldn't reach GitHub. Check your connection and try again."
        } catch {
            statusMessage = "Couldn't verify the token: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        do {
            try await credentialStore.deleteToken()
            connectedLogin = nil
            statusMessage = "Disconnected from GitHub."
        } catch {
            statusMessage = "Couldn't disconnect: \(error.localizedDescription)"
        }
    }
}
