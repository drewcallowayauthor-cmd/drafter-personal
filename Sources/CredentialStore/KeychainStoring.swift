import DrafterCore
import Foundation
import Security

/// Abstraction over the macOS Keychain (§5.3: "Store in the macOS Keychain, never in a
/// plist, never in `project.json`, never in `.git/config`"). Every caller depends on this
/// protocol rather than `Security` directly, so save/load/delete logic can be unit tested
/// against a fake without touching the real Keychain.
public protocol KeychainStoring: Sendable {
    func save(_ data: Data, account: String, service: String) async throws
    func read(account: String, service: String) async throws -> Data?
    func delete(account: String, service: String) async throws
}

/// `Security` framework-backed implementation used at runtime.
public struct LiveKeychainStore: KeychainStoring {
    public init() {}

    public func save(_ data: Data, account: String, service: String) throws {
        var query = baseQuery(account: account, service: service)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess { return }

        guard addStatus == errSecDuplicateItem else {
            throw DrafterError.keychainFailed(status: addStatus)
        }

        let updateQuery = baseQuery(account: account, service: service)
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw DrafterError.keychainFailed(status: updateStatus)
        }
    }

    public func read(account: String, service: String) throws -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw DrafterError.keychainFailed(status: status)
        }
        return result as? Data
    }

    public func delete(account: String, service: String) throws {
        let query = baseQuery(account: account, service: service)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DrafterError.keychainFailed(status: status)
        }
    }

    private func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
    }
}
