import DrafterTestSupport
import Testing
@testable import CredentialStore

@Suite("CredentialStore")
struct CredentialStoreTests {
    @Test("saving then loading returns the same token")
    func saveThenLoadRoundTrips() async throws {
        let store = CredentialStore(keychain: MockKeychainStore())
        try await store.saveToken("ghp_abc123")
        let loaded = try await store.loadToken()
        #expect(loaded == "ghp_abc123")
    }

    @Test("loading with nothing saved returns nil")
    func loadWithNothingSavedReturnsNil() async throws {
        let store = CredentialStore(keychain: MockKeychainStore())
        let loaded = try await store.loadToken()
        #expect(loaded == nil)
    }

    @Test("saving twice overwrites rather than duplicating")
    func savingTwiceOverwrites() async throws {
        let store = CredentialStore(keychain: MockKeychainStore())
        try await store.saveToken("first-token")
        try await store.saveToken("second-token")
        let loaded = try await store.loadToken()
        #expect(loaded == "second-token")
    }

    @Test("deleting removes the token")
    func deletingRemovesToken() async throws {
        let store = CredentialStore(keychain: MockKeychainStore())
        try await store.saveToken("ghp_abc123")
        try await store.deleteToken()
        let loaded = try await store.loadToken()
        #expect(loaded == nil)
    }

    @Test("deleting when nothing is saved does not throw")
    func deletingWithNothingSavedDoesNotThrow() async throws {
        let store = CredentialStore(keychain: MockKeychainStore())
        try await store.deleteToken()
    }
}
