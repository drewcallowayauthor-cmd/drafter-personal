import DrafterCore
import Foundation
import Security

/// Owns the single GitHub Personal Access Token (§5.3) in the Keychain. One token per
/// app — v1 supports a single GitHub account — so there's no per-project account
/// namespacing to manage here.
public actor CredentialStore {
    private static let service = "com.drafter.github"
    private static let account = "personal-access-token"

    private let keychain: KeychainStoring

    public init(keychain: KeychainStoring = LiveKeychainStore()) {
        self.keychain = keychain
    }

    public func saveToken(_ token: String) async throws {
        guard let data = token.data(using: .utf8) else {
            throw DrafterError.keychainFailed(status: errSecParam)
        }
        try await keychain.save(data, account: Self.account, service: Self.service)
    }

    public func loadToken() async throws -> String? {
        guard let data = try await keychain.read(account: Self.account, service: Self.service) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteToken() async throws {
        try await keychain.delete(account: Self.account, service: Self.service)
    }
}
