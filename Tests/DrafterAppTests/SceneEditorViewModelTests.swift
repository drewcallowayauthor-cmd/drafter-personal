import DrafterTestSupport
import Foundation
import Testing
@testable import DrafterApp

@MainActor
@Suite("SceneEditorViewModel autosave")
struct SceneEditorViewModelTests {
    @Test("editing does not write to disk before the debounce elapses")
    func editingDoesNotWriteBeforeDebounce() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer, autosaveDelay: .milliseconds(100))

        viewModel.open(url: url)
        viewModel.updateBody("Edited body.")

        try await Task.sleep(for: .milliseconds(30))
        #expect(writer.writes.isEmpty)
    }

    @Test("editing writes to disk once the debounce elapses")
    func editingWritesAfterDebounce() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer, autosaveDelay: .milliseconds(50))

        viewModel.open(url: url)
        viewModel.updateBody("Edited body.")

        try await Task.sleep(for: .milliseconds(150))
        #expect(writer.writes.count == 1)
        #expect(writer.writes.first?.url == url)
        #expect(viewModel.document?.isDirty == false)
    }

    @Test("rapid edits reset the debounce so only the final content is written")
    func rapidEditsCoalesceIntoOneWrite() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer, autosaveDelay: .milliseconds(80))

        viewModel.open(url: url)
        viewModel.updateBody("First edit.")
        try await Task.sleep(for: .milliseconds(30))
        viewModel.updateBody("Second edit.")
        try await Task.sleep(for: .milliseconds(30))
        viewModel.updateBody("Final edit.")

        try await Task.sleep(for: .milliseconds(150))
        #expect(writer.writes.count == 1)
        let written = String(data: writer.writes.first!.data, encoding: .utf8)
        #expect(written?.contains("Final edit.") == true)
    }

    @Test("saveNow writes immediately without waiting for the debounce")
    func saveNowWritesImmediately() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer, autosaveDelay: .seconds(60))

        viewModel.open(url: url)
        viewModel.updateBody("Blur-triggered save.")
        viewModel.saveNow()

        #expect(writer.writes.count == 1)
        #expect(viewModel.document?.isDirty == false)
    }

    @Test("saveNow is a no-op when nothing changed")
    func saveNowNoOpWhenClean() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer)

        viewModel.open(url: url)
        viewModel.saveNow()

        #expect(writer.writes.isEmpty)
    }

    @Test("close() flushes a pending edit before clearing the document")
    func closeFlushesPendingEdit() async throws {
        let url = try writeScene()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = MockAtomicFileWriter()
        let viewModel = SceneEditorViewModel(fileWriter: writer, autosaveDelay: .seconds(60))

        viewModel.open(url: url)
        viewModel.updateBody("Edited right before switching scenes.")
        viewModel.close()

        #expect(writer.writes.count == 1)
        #expect(viewModel.document == nil)
    }

    private func writeScene() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("scene.md")
        try Data("---\nsynopsis: \nstatus: draft\ncompile: true\nnotes: \n---\n\nOriginal.".utf8).write(to: url)
        return url
    }
}
