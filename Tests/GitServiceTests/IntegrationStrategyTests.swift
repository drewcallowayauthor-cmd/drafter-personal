import Testing
@testable import GitService

@Suite("IntegrationStrategy")
struct IntegrationStrategyTests {
    @Test("identical when neither ahead nor behind")
    func identicalWhenEven() {
        #expect(IntegrationStrategy.decide(ahead: 0, behind: 0) == .identical)
    }

    @Test("fast-forward when only behind")
    func fastForwardWhenOnlyBehind() {
        #expect(IntegrationStrategy.decide(ahead: 0, behind: 4) == .fastForward)
    }

    @Test("push when only ahead")
    func pushWhenOnlyAhead() {
        #expect(IntegrationStrategy.decide(ahead: 2, behind: 0) == .push)
    }

    @Test("merge when diverged in both directions")
    func mergeWhenDiverged() {
        #expect(IntegrationStrategy.decide(ahead: 1, behind: 1) == .merge)
        #expect(IntegrationStrategy.decide(ahead: 5, behind: 3) == .merge)
    }
}
