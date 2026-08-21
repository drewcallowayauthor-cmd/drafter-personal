import Foundation
import Testing
@testable import DrafterApp

@Suite("BundledFonts")
struct BundledFontsTests {
    @Test("the app bundles EB Garamond's regular and italic .ttf files")
    func bundlesEBGaramondFiles() throws {
        let fontsDirectory = try #require(BundledFonts.fontsDirectoryURL)
        let ebGaramondDirectory = fontsDirectory.appendingPathComponent("EBGaramond")

        let files = Set(try FileManager.default.contentsOfDirectory(atPath: ebGaramondDirectory.path))
        #expect(files.contains("EBGaramond.ttf"))
        #expect(files.contains("EBGaramond-Italic.ttf"))
        #expect(files.contains("OFL.txt"))
    }
}
