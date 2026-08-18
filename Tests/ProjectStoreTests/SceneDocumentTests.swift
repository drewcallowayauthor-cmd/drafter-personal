import Foundation
import Testing
@testable import ProjectStore

@Suite("SceneDocument")
struct SceneDocumentTests {
    @Test("loading from disk is not dirty")
    func loadIsNotDirty() throws {
        let url = try writeScene("""
        ---
        synopsis: Test.
        status: draft
        compile: true
        ---

        Original body.
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try SceneDocument.load(from: url)

        #expect(document.isDirty == false)
        #expect(document.body == "Original body.")
    }

    @Test("editing the body marks the document dirty")
    func editingBodyMarksDirty() throws {
        let url = try writeScene("---\nsynopsis: \nstatus: draft\ncompile: true\nnotes: \n---\n\nOriginal.")
        defer { try? FileManager.default.removeItem(at: url) }

        var document = try SceneDocument.load(from: url)
        document.body = "Edited."

        #expect(document.isDirty == true)
    }

    @Test("markedSaved clears dirty state without changing content")
    func markedSavedClearsDirty() throws {
        let url = try writeScene("---\nsynopsis: \nstatus: draft\ncompile: true\nnotes: \n---\n\nOriginal.")
        defer { try? FileManager.default.removeItem(at: url) }

        var document = try SceneDocument.load(from: url)
        document.body = "Edited."
        let saved = document.markedSaved()

        #expect(saved.isDirty == false)
        #expect(saved.body == "Edited.")
    }

    @Test("editing front matter also marks the document dirty")
    func editingFrontMatterMarksDirty() throws {
        let url = try writeScene("---\nsynopsis: \nstatus: draft\ncompile: true\nnotes: \n---\n\nText.")
        defer { try? FileManager.default.removeItem(at: url) }

        var document = try SceneDocument.load(from: url)
        document.frontMatter.status = .final

        #expect(document.isDirty == true)
    }

    private func writeScene(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("scene.md")
        try Data(contents.utf8).write(to: url)
        return url
    }
}
