import DrafterTestSupport
import Foundation
import Testing
@testable import ProjectStore

@Suite("ProjectMetadataStore")
struct ProjectMetadataStoreTests {
    @Test("decodes the project.json shape from the design doc")
    func decodesDesignDocExample() throws {
        let json = """
        {
          "schemaVersion": 2,
          "id": "F4C2A1E9-0000-0000-0000-000000000000",
          "title": "The Last Shift",
          "subtitle": "",
          "author": "Tim Fleet",
          "series": { "name": "", "number": null },
          "copyrightYear": 2026,
          "publisher": "",
          "isbn": "",
          "language": "en-US",
          "description": "",
          "target": { "words": 45000 },
          "compile": {
            "chapterTitleFormat": "Chapter {n}",
            "sceneSeparator": "* * *",
            "includeFrontMatter": true,
            "includeBackMatter": true,
            "coverImage": "Resources/cover.jpg"
          },
          "print": {
            "trimSize": "5x8",
            "bodyFont": "Palatino",
            "bodyPointSize": 11.5,
            "leading": 1.46,
            "chapterOpensOn": "either"
          }
        }
        """
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(json.utf8).write(to: directory.appendingPathComponent("project.json"))

        let store = ProjectMetadataStore(fileWriter: MockAtomicFileWriter())
        let metadata = try store.load(from: directory)

        #expect(metadata.title == "The Last Shift")
        #expect(metadata.author == "Tim Fleet")
        #expect(metadata.target.words == 45000)
        #expect(metadata.compile.chapterTitleFormat == "Chapter {n}")
        #expect(metadata.print.trimSize == "5x8")
        #expect(metadata.series.number == nil)
    }

    @Test("save writes atomically-written JSON that round-trips through load")
    func saveThenLoadRoundTrips() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let writer = MockAtomicFileWriter()
        let store = ProjectMetadataStore(fileWriter: writer)

        try store.save(original, to: directory)

        #expect(writer.writes.count == 1)
        #expect(writer.writes.first?.url == directory.appendingPathComponent("project.json"))

        // Write the recorded bytes to disk (the mock doesn't touch disk) and load them back.
        try writer.writes[0].data.write(to: directory.appendingPathComponent("project.json"))
        let reloaded = try store.load(from: directory)

        #expect(reloaded == original)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
