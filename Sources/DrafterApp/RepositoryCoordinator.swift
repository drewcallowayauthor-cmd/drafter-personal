import CredentialStore
import DrafterCore
import Foundation
import GitService

/// §7's `SyncCoordinator` role, minus the ongoing fetch/merge/push loop (that's
/// `GitService.SyncCoordinator`): repo init, commit triggers, and connecting a fresh
/// local repo to GitHub (§5.2). One instance per open project; owns the working tree's
/// relationship with git so the rest of the app just calls `commit(trigger:)` and
/// doesn't think about staging, empty commits, or identity.
public actor RepositoryCoordinator: CheckpointCoordinating {
    private let gitService: GitService
    private let workingTree: URL
    private let machineName: String

    public init(gitService: GitService, workingTree: URL, machineName: String = RepositoryCoordinator.defaultMachineName()) {
        self.gitService = gitService
        self.workingTree = workingTree
        self.machineName = machineName
    }

    /// Initializes a git repo in-place if one doesn't already exist, and sets a local
    /// identity so commits succeed even on a machine with no global git config. The
    /// email is a placeholder — §5.2 replaces it with the real GitHub account email
    /// once a project connects to GitHub (M3); until then, anything unique is fine
    /// since these commits never leave the machine.
    public func ensureInitialized(authorName: String) async throws {
        let gitDirectory = workingTree.appendingPathComponent(".git")
        guard !FileManager.default.fileExists(atPath: gitDirectory.path) else { return }

        try await gitService.initRepository(in: workingTree)
        try await gitService.configureIdentity(
            name: authorName,
            email: Self.placeholderEmail(for: authorName),
            in: workingTree
        )
    }

    /// Commits per §5.4's trigger table if — and only if — there's actually something
    /// to commit. Never produces an empty commit.
    @discardableResult
    public func commit(trigger: CommitTrigger) async throws -> Bool {
        guard try await gitService.hasUncommittedChanges(in: workingTree) else { return false }
        try await gitService.stageAll(in: workingTree)
        try await gitService.commit(message: CommitMessageBuilder.message(for: trigger, machine: machineName), in: workingTree)
        return true
    }

    /// §5.2's new-project connection sequence: create the private repo, point `origin`
    /// at it, replace the placeholder git identity with the real GitHub account email,
    /// then push. Callers are expected to catch failures here and fall back to the
    /// "Not synced" local-only state (§5.2) — a taken name, no token, or being offline
    /// must never block project creation itself.
    @discardableResult
    public func connectToGitHub(
        repositoryName: String,
        authorName: String,
        apiClient: GitHubAPIClient,
        token: String
    ) async throws -> GitHubRepository {
        let repository = try await apiClient.createRepository(name: repositoryName, token: token)
        try await gitService.addRemote(url: repository.cloneURL.absoluteString, in: workingTree)

        let user = try await apiClient.currentUser(token: token)
        let email = user.email ?? "\(user.login)@users.noreply.github.com"
        try await gitService.configureIdentity(name: authorName, email: email, in: workingTree)

        try await gitService.pushSettingUpstream(in: workingTree)
        return repository
    }

    public static func defaultMachineName() -> String {
        let hostName = ProcessInfo.processInfo.hostName
        return hostName.hasSuffix(".local") ? String(hostName.dropLast(".local".count)) : hostName
    }

    private static func placeholderEmail(for authorName: String) -> String {
        let slug = authorName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(slug.isEmpty ? "writer" : slug)@drafter.local"
    }
}
