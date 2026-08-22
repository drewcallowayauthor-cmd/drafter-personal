import Testing
@testable import CompileService

@Suite("DOCXHeaderPatcher")
struct DOCXHeaderPatcherTests {
    @Test("replaces both tokens with the given values")
    func replacesTokens() {
        let header = "<w:t>AUTHORLASTNAME / MANUSCRIPTTITLE / </w:t>"
        let patched = DOCXHeaderPatcher.patchHeader(header, authorLastName: "Doe", title: "My Book")
        #expect(patched == "<w:t>Doe / My Book / </w:t>")
    }

    @Test("escapes an ampersand in the author last name or title")
    func escapesAmpersand() {
        let header = "<w:t>AUTHORLASTNAME / MANUSCRIPTTITLE / </w:t>"
        let patched = DOCXHeaderPatcher.patchHeader(header, authorLastName: "Smith & Jones", title: "Salt & Sea")
        #expect(patched == "<w:t>Smith &amp; Jones / Salt &amp; Sea / </w:t>")
    }

    @Test("swaps Times New Roman for the requested font")
    func swapsFont() {
        let styles = "<w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" />"
        let patched = DOCXHeaderPatcher.applyBodyFont("Courier New", to: styles)
        #expect(patched == "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" />")
    }

    @Test("is a no-op when the font is already Times New Roman")
    func noOpForTimesNewRoman() {
        let styles = "<w:rFonts w:ascii=\"Times New Roman\" />"
        #expect(DOCXHeaderPatcher.applyBodyFont("Times New Roman", to: styles) == styles)
    }

    @Test("font comparison is case-insensitive")
    func caseInsensitiveNoOp() {
        let styles = "<w:rFonts w:ascii=\"Times New Roman\" />"
        #expect(DOCXHeaderPatcher.applyBodyFont("times new roman", to: styles) == styles)
    }
}
