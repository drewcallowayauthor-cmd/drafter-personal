import CredentialStore
import DrafterCore
import Foundation
import GitService

/// GitHub connect/reconnect flows for `ProjectViewModel`, split out to keep the main
/// file's file/type-body lengths under SwiftLint's limits.
extension ProjectViewModel {
    /// §5.2's "Connect to GitHub" action for a project that's open but not yet synced
    /// — it predates having a saved token, or GitHub connection failed when it was
    /// created (§5.2: "still create the project locally... mark it Not synced with a
    /// Connect to GitHub action"). Rebuilds this project's git wiring via `attach`
    /// afterward so the newly-added remote actually starts the sync loop, rather than
    /// leaving `syncScheduler` nil until the next reopen.
    func connectToGitHub() async {
        await serialized { await self.connectToGitHubImpl() }
    }

    private func connectToGitHubImpl() async {
        errorMessage = nil
        syncStatusMessage = nil
        guard let project, let workingTreeRoot, let metadata, metadata.versionControl == .git else { return }
        guard let token = await Self.loadTokenIfAvailable(), !token.isEmpty else {
            syncStatusMessage = "Add a GitHub token in Settings first."
            return
        }

        let freshGitService = Self.makeGitService(authToken: token)
        if await Self.hasRemoteLogging(freshGitService, in: workingTreeRoot) {
            syncStatusMessage = "Already connected to GitHub."
            return
        }

        let repositoryCoordinator = RepositoryCoordinator(gitService: freshGitService, workingTree: workingTreeRoot)
        do {
            let repository = try await repositoryCoordinator.connectToGitHub(
                repositoryName: Self.slug(for: metadata.title),
                authorName: metadata.author,
                apiClient: GitHubAPIClient(),
                token: token
            )
            syncStatusMessage = "Synced to \(repository.htmlURL.absoluteString)"
            try await attach(
                project: project,
                root: workingTreeRoot,
                gitService: freshGitService,
                repositoryCoordinator: repositoryCoordinator,
                metadata: metadata
            )
        } catch {
            syncStatusMessage = "Couldn't connect to GitHub — \(error.localizedDescription)"
        }
    }

    /// Best-effort — failures here are §5.2's "Not synced" path, not a thrown error.
    func connectToGitHubIfPossible(
        repositoryName: String,
        authorName: String,
        repositoryCoordinator: RepositoryCoordinator,
        token: String?
    ) async {
        guard let token else {
            syncStatusMessage = "Not synced to GitHub"
            return
        }
        do {
            let repository = try await repositoryCoordinator.connectToGitHub(
                repositoryName: repositoryName,
                authorName: authorName,
                apiClient: GitHubAPIClient(),
                token: token
            )
            syncStatusMessage = "Synced to \(repository.htmlURL.absoluteString)"
        } catch {
            syncStatusMessage = "Not synced to GitHub — \(error.localizedDescription)"
        }
    }

    /// §12.2 point 4's resolution: called when Settings saves a newly verified token.
    /// `GitService.authToken` is immutable once constructed, so simply retrying with
    /// the existing `syncScheduler` would just fail the same way again with the same
    /// stale token — this rebuilds the project's git wiring (via `attach`, same as a
    /// fresh open) so the new token actually gets used, then that rebuild's own
    /// `SyncScheduler.start()` retries immediately rather than waiting out the next
    /// periodic tick.
    func refreshCredentialsAndResync() async {
        await serialized { await self.refreshCredentialsAndResyncImpl() }
    }

    private func refreshCredentialsAndResyncImpl() async {
        guard let project, let workingTreeRoot, let metadata, metadata.versionControl == .git else { return }
        errorMessage = nil
        let token = await Self.loadTokenIfAvailable()
        let gitService = Self.makeGitService(authToken: token)
        do {
            try await attach(project: project, root: workingTreeRoot, gitService: gitService, metadata: metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The stored token is best-effort throughout `ProjectViewModel`: most opens have
    /// no GitHub remote at all, so a Keychain miss/failure just falls back to an
    /// unauthenticated `GitService` rather than blocking the open — but a failure that
    /// isn't "there's simply no token saved" should still leave a trace rather than
    /// silently behaving as if the user were never connected.
    static func loadTokenIfAvailable() async -> String? {
        do {
            return try await CredentialStore().loadToken()
        } catch {
            DrafterLog.app.error("Failed to load the saved GitHub token: \(error, privacy: .public)")
            return nil
        }
    }

    /// Tools pane's git override (§12), falling back to `GitService`'s own
    /// `/usr/bin/git` default when unset.
    static func makeGitService(authToken: String?) -> GitService {
        if let overridePath = AppPreferences.shared.gitPathOverride {
            return GitService(
                processRunner: LiveProcessRunner(),
                gitExecutableURL: URL(fileURLWithPath: overridePath),
                authToken: authToken
            )
        }
        return GitService(processRunner: LiveProcessRunner(), authToken: authToken)
    }

    /// A failed `remoteURL` check is treated the same as "no remote configured yet" —
    /// worst case this re-attempts a connect that turns out to already exist, which
    /// `RepositoryCoordinator.connectToGitHub` handles gracefully — but it's still
    /// worth a log line so a spurious "reconnect" isn't a total mystery later.
    static func hasRemoteLogging(_ gitService: GitService, in workingTree: URL) async -> Bool {
        do {
            return try await gitService.remoteURL(in: workingTree) != nil
        } catch {
            DrafterLog.app.error("Failed to check for an existing remote: \(error, privacy: .public)")
            return false
        }
    }
}
