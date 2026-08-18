import Foundation
import Testing
@testable import DrafterCore

@Suite("BinaryResolver")
struct BinaryResolverTests {
    @Test("finds an executable in the first matching candidate directory")
    func findsExecutableInCandidateDirectory() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("pandoc")
        try makeExecutable(at: binary)

        let resolved = BinaryResolver.resolve(
            name: "pandoc",
            candidateDirectories: [directory.path],
            environment: [:]
        )

        #expect(resolved == binary)
    }

    @Test("skips a candidate directory with no matching file and checks the next one")
    func skipsNonMatchingDirectories() throws {
        let emptyDirectory = try makeTempDirectory()
        let realDirectory = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: emptyDirectory)
            try? FileManager.default.removeItem(at: realDirectory)
        }
        let binary = realDirectory.appendingPathComponent("typst")
        try makeExecutable(at: binary)

        let resolved = BinaryResolver.resolve(
            name: "typst",
            candidateDirectories: [emptyDirectory.path, realDirectory.path],
            environment: [:]
        )

        #expect(resolved == binary)
    }

    @Test("falls back to searching the PATH environment variable")
    func fallsBackToPATH() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("pandoc")
        try makeExecutable(at: binary)

        let resolved = BinaryResolver.resolve(
            name: "pandoc",
            candidateDirectories: [],
            environment: ["PATH": "/nonexistent:\(directory.path)"]
        )

        #expect(resolved == binary)
    }

    @Test("a non-executable file with the right name is not resolved")
    func nonExecutableFileIsNotResolved() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notExecutable = directory.appendingPathComponent("pandoc")
        try Data("not a binary".utf8).write(to: notExecutable)

        let resolved = BinaryResolver.resolve(name: "pandoc", candidateDirectories: [directory.path], environment: [:])

        #expect(resolved == nil)
    }

    @Test("returns nil when the binary is nowhere to be found")
    func returnsNilWhenNotFound() throws {
        let resolved = BinaryResolver.resolve(
            name: "definitely-not-a-real-binary",
            candidateDirectories: ["/nonexistent"],
            environment: ["PATH": "/also-nonexistent"]
        )

        #expect(resolved == nil)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(at url: URL) throws {
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
