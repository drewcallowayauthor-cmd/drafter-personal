import Testing
@testable import CompileService

@Suite("SMFEndOfManuscriptMarker")
struct SMFEndOfManuscriptMarkerTests {
    @Test("appends a centered * * * on a new line after the manuscript body")
    func appendsCenteredMarker() {
        let output = SMFEndOfManuscriptMarker.append(to: "The last line of the story.")
        #expect(output.hasPrefix("The last line of the story.\n\n"))
        #expect(output.contains("<w:pStyle w:val=\"SMFEndMark\" />"))
        #expect(output.contains("<w:t>* * *</w:t>"))
    }
}
