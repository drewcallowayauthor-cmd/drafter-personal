import Foundation
import Testing
@testable import DrafterCore

@Suite("LiveAtomicFileWriter")
struct AtomicFileWriterTests {
    @Test("writes new content and never leaves a temp file behind")
    func writesAndCleansUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("scene.md")
        let writer = LiveAtomicFileWriter()

        try writer.write(Data("first".utf8), to: target)
        #expect(try String(contentsOf: target, encoding: .utf8) == "first")

        try writer.write(Data("second".utf8), to: target)
        #expect(try String(contentsOf: target, encoding: .utf8) == "second")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }
}
