import Testing
@testable import DrafterCore

@Suite("SyncStateMachine")
struct SyncStateMachineTests {
    @Test("legal happy-path transitions succeed")
    func happyPath() async throws {
        let machine = SyncStateMachine()
        try await machine.transition(to: .fetching)
        try await machine.transition(to: .merging)
        try await machine.transition(to: .pushing)
        try await machine.transition(to: .idle)
        #expect(await machine.state == .idle)
    }

    @Test("idle cannot jump straight to pushing")
    func illegalSkip() async throws {
        let machine = SyncStateMachine()
        await #expect(throws: SyncStateError.self) {
            try await machine.transition(to: .pushing)
        }
    }

    @Test("conflicted is terminal until resolved")
    func conflictedIsTerminalUntilResolved() async throws {
        let machine = SyncStateMachine()
        try await machine.transition(to: .fetching)
        try await machine.transition(to: .merging)
        try await machine.transition(to: .conflicted(paths: ["Manuscript/scene.md"]))

        await #expect(throws: SyncStateError.self) {
            try await machine.transition(to: .pushing)
        }
        await #expect(throws: SyncStateError.self) {
            try await machine.transition(to: .fetching)
        }

        try await machine.transition(to: .merging)
        #expect(await machine.state == .merging)
    }

    @Test("offline can be entered from idle and returns to idle")
    func offlineRoundTrip() async throws {
        let machine = SyncStateMachine()
        try await machine.transition(to: .offline(pendingCommits: 3))
        try await machine.transition(to: .fetching)
        try await machine.transition(to: .idle)
        #expect(await machine.state == .idle)
    }
}
