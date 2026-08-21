import Foundation
import Testing
@testable import DrafterApp

@Suite("OpenProjectRegistry")
struct OpenProjectRegistryTests {
    @Test("a second registration for the same root is refused until the first unregisters")
    func refusesDuplicateRegistration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = OpenProjectRegistry.shared

        #expect(await registry.tryRegister(root) == true)
        #expect(await registry.tryRegister(root) == false)

        await registry.unregister(root)
        #expect(await registry.tryRegister(root) == true)
    }

    @Test("different roots register independently")
    func differentRootsDoNotCollide() async throws {
        let root1 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = OpenProjectRegistry.shared

        #expect(await registry.tryRegister(root1) == true)
        #expect(await registry.tryRegister(root2) == true)
    }

    @Test("a symlinked path and its real path collide as the same project")
    func resolvesSymlinksBeforeComparing() async throws {
        let realRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realRoot) }
        let symlinkRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)
        defer { try? FileManager.default.removeItem(at: symlinkRoot) }
        let registry = OpenProjectRegistry.shared

        #expect(await registry.tryRegister(realRoot) == true)
        #expect(await registry.tryRegister(symlinkRoot) == false)
    }
}
