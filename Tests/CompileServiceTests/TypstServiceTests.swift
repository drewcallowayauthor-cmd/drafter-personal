import DrafterCore
import DrafterTestSupport
import Foundation
import Testing
@testable import CompileService

@Suite("TypstService")
struct TypstServiceTests {
    private let workingDirectory = URL(fileURLWithPath: "/tmp/project/Build")
    private let typstURL = URL(fileURLWithPath: "/usr/local/bin/typst")

    @Test("compile runs typst compile <input> <output>")
    func compileRunsCorrectCommand() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "typst"
        )
        let service = TypstService(processRunner: runner, typstExecutableURL: typstURL)

        _ = try await service.compile(inputPath: "main.typ", outputPath: "../Book.pdf", in: workingDirectory)

        let invocations = await runner.invocations
        #expect(invocations.first?.arguments == ["compile", "main.typ", "../Book.pdf"])
        #expect(invocations.first?.currentDirectoryURL == workingDirectory)
    }

    @Test("compile adds a --font-path argument per font directory, before the input/output paths")
    func compileAddsFontPathArguments() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 0, standardOutput: "", standardError: ""), forExecutableNamed: "typst"
        )
        let service = TypstService(processRunner: runner, typstExecutableURL: typstURL)

        _ = try await service.compile(
            inputPath: "main.typ",
            outputPath: "../Book.pdf",
            fontPaths: ["/App/Fonts/EBGaramond"],
            in: workingDirectory
        )

        let invocations = await runner.invocations
        let expectedArguments = ["compile", "--font-path", "/App/Fonts/EBGaramond", "main.typ", "../Book.pdf"]
        #expect(invocations.first?.arguments == expectedArguments)
    }

    @Test("a non-zero exit returns the result with stderr intact rather than throwing")
    func nonZeroExitReturnsResultNotThrow() async throws {
        let runner = MockProcessRunner()
        await runner.script(
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "error: unknown variable: foo"),
            forExecutableNamed: "typst"
        )
        let service = TypstService(processRunner: runner, typstExecutableURL: typstURL)

        let result = try await service.compile(inputPath: "main.typ", outputPath: "out.pdf", in: workingDirectory)

        #expect(result.succeeded == false)
        #expect(result.standardError == "error: unknown variable: foo")
    }
}
