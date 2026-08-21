import CredentialStore
import DrafterCore
import Foundation

/// An in-memory `KeychainStoring` fake — no real Keychain access, so tests are fast and
/// don't prompt for Keychain access or leave real secrets behind.
public actor MockKeychainStore: KeychainStoring {
    private var storage: [String: Data] = [:]

    public init() {}

    private func key(account: String, service: String) -> String { "\(service)|\(account)" }

    public func save(_ data: Data, account: String, service: String) throws {
        storage[key(account: account, service: service)] = data
    }

    public func read(account: String, service: String) throws -> Data? {
        storage[key(account: account, service: service)]
    }

    public func delete(account: String, service: String) throws {
        storage.removeValue(forKey: key(account: account, service: service))
    }
}
