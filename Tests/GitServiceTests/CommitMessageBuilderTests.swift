import Testing
@testable import GitService

@Suite("CommitMessageBuilder")
struct CommitMessageBuilderTests {
    @Test("autosave matches the §5.4 example exactly")
    func autosaveMatchesExample() {
        let message = CommitMessageBuilder.message(
            for: .autosave(filesChanged: 3, wordDelta: 412),
            machine: "Josiah-MacBook-Pro"
        )
        #expect(message == "autosave — 3 files, +412 words\n\nMachine: Josiah-MacBook-Pro")
    }

    @Test("session end groups thousands, matching the §5.4 example")
    func sessionEndGroupsThousands() {
        let message = CommitMessageBuilder.message(for: .sessionEnd(wordDelta: 1840), machine: "Josiah-Mac-Studio")
        #expect(message == "session end — +1,840 words\n\nMachine: Josiah-Mac-Studio")
    }

    @Test("focus lost has no word count")
    func focusLostHasNoWordCount() {
        let message = CommitMessageBuilder.message(for: .focusLost, machine: "Machine")
        #expect(message.hasPrefix("autosave (focus lost)\n\n"))
    }

    @Test("pre-export subject is literal")
    func preExportSubjectIsLiteral() {
        let message = CommitMessageBuilder.message(for: .preExport, machine: "Machine")
        #expect(message.hasPrefix("pre-export\n\n"))
    }

    @Test("checkpoint with no label omits the dash")
    func checkpointWithNoLabel() {
        let message = CommitMessageBuilder.message(for: .checkpoint(label: nil), machine: "Machine")
        #expect(message.hasPrefix("checkpoint\n\n"))
    }

    @Test("checkpoint with a label includes it")
    func checkpointWithLabel() {
        let message = CommitMessageBuilder.message(for: .checkpoint(label: "before rewrite"), machine: "Machine")
        #expect(message.hasPrefix("checkpoint — before rewrite\n\n"))
    }

    @Test("singularizes file and word counts of exactly one")
    func singularizesCountsOfOne() {
        let message = CommitMessageBuilder.message(for: .autosave(filesChanged: 1, wordDelta: 1), machine: "M")
        #expect(message.hasPrefix("autosave — 1 file, +1 word\n\n"))
    }

    @Test("a negative word delta (net deletion) is signed with a minus")
    func negativeWordDeltaIsSignedWithMinus() {
        let message = CommitMessageBuilder.message(for: .sessionEnd(wordDelta: -50), machine: "M")
        #expect(message.hasPrefix("session end — -50 words\n\n"))
    }
}
