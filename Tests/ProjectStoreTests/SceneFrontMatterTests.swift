import Testing
@testable import ProjectStore

@Suite("SceneFrontMatter")
struct SceneFrontMatterTests {
    @Test("parses the design doc's example scene")
    func parsesDesignDocExample() {
        let scene = """
        ---
        synopsis: Sam takes over the board and finds Room Nine already occupied.
        status: draft
        compile: true
        ---

        The board was wrong.
        """
        let (frontMatter, body) = SceneFrontMatter.parse(scene)

        #expect(frontMatter.synopsis == "Sam takes over the board and finds Room Nine already occupied.")
        #expect(frontMatter.status == .draft)
        #expect(frontMatter.compile == true)
        #expect(body == "The board was wrong.")
    }

    @Test("a scene with no front matter block becomes the whole body with default metadata")
    func noFrontMatterBlock() {
        let (frontMatter, body) = SceneFrontMatter.parse("Just prose, no front matter.")

        #expect(frontMatter == SceneFrontMatter())
        #expect(body == "Just prose, no front matter.")
    }

    @Test("unknown keys are ignored rather than throwing")
    func ignoresUnknownKeys() {
        let scene = """
        ---
        synopsis: Test.
        future_field: something
        status: revised
        ---

        Body text.
        """
        let (frontMatter, body) = SceneFrontMatter.parse(scene)

        #expect(frontMatter.synopsis == "Test.")
        #expect(frontMatter.status == .revised)
        #expect(body == "Body text.")
    }

    @Test("compile defaults true and status defaults draft when absent")
    func defaultsWhenFieldsAbsent() {
        let scene = """
        ---
        synopsis: Only a synopsis.
        ---

        Body.
        """
        let (frontMatter, _) = SceneFrontMatter.parse(scene)

        #expect(frontMatter.compile == true)
        #expect(frontMatter.status == .draft)
    }

    @Test("serialize then parse round-trips")
    func serializeRoundTrips() {
        let original = SceneFrontMatter(
            synopsis: "A short summary.",
            status: .final,
            compile: false,
            notes: "scratch note"
        )
        let serialized = SceneFrontMatter.serialize(original, body: "Final prose.")
        let (parsed, body) = SceneFrontMatter.parse(serialized)

        #expect(parsed == original)
        #expect(body == "Final prose.")
    }
}
