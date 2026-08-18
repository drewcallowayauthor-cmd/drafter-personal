import Testing
@testable import DrafterApp

@Suite("CommitSubjectWordDelta")
struct CommitSubjectWordDeltaTests {
    @Test("parses a positive delta from an autosave subject")
    func parsesPositiveDelta() {
        #expect(CommitSubjectWordDelta.parse("autosave — 3 files, +412 words") == 412)
    }

    @Test("parses a thousands-grouped delta from a session end subject")
    func parsesGroupedDelta() {
        #expect(CommitSubjectWordDelta.parse("session end — +1,840 words") == 1840)
    }

    @Test("parses a negative delta")
    func parsesNegativeDelta() {
        #expect(CommitSubjectWordDelta.parse("session end — -50 words") == -50)
    }

    @Test("checkpoint subjects have no word count and parse to nil")
    func checkpointParsesToNil() {
        #expect(CommitSubjectWordDelta.parse("checkpoint") == nil)
        #expect(CommitSubjectWordDelta.parse("checkpoint — before rewrite") == nil)
    }

    @Test("pre-export subject parses to nil")
    func preExportParsesToNil() {
        #expect(CommitSubjectWordDelta.parse("pre-export") == nil)
    }

    @Test("focus-lost autosave subject has no word count and parses to nil")
    func focusLostParsesToNil() {
        #expect(CommitSubjectWordDelta.parse("autosave (focus lost)") == nil)
    }

    @Test("singular word count parses correctly")
    func singularWordParses() {
        #expect(CommitSubjectWordDelta.parse("autosave — 1 file, +1 word") == 1)
    }
}
