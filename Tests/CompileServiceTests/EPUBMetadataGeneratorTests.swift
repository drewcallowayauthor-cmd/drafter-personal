import Foundation
import ProjectStore
import Testing
@testable import CompileService

@Suite("EPUBMetadataGenerator")
struct EPUBMetadataGeneratorTests {
    private var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 18
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("includes the core fields")
    func includesCoreFields() {
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("title: \"The Last Shift\""))
        #expect(yaml.contains("creator: \"Tim Fleet\""))
        #expect(yaml.contains("date: \"2026-08-18\""))
        #expect(yaml.contains("language: \"en-US\""))
        #expect(yaml.contains("rights: \"Copyright © 2026 by Tim Fleet\""))
    }

    @Test("uses the ISBN as the identifier when present")
    func usesISBNWhenPresent() {
        let metadata = ProjectMetadata(
            title: "The Last Shift",
            author: "Tim Fleet",
            copyrightYear: 2026,
            isbn: "978-0-000000-00-0"
        )
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("identifier: \"978-0-000000-00-0\""))
    }

    @Test("falls back to project.id as the identifier when there is no ISBN")
    func fallsBackToProjectIDWithoutISBN() {
        let metadata = ProjectMetadata(id: "F4C2A1E9-TEST", title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("identifier: \"F4C2A1E9-TEST\""))
    }

    @Test("omits subtitle, publisher, and description lines when they're empty")
    func omitsEmptyOptionalFields() {
        let metadata = ProjectMetadata(title: "The Last Shift", author: "Tim Fleet", copyrightYear: 2026)
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("subtitle:") == false)
        #expect(yaml.contains("publisher:") == false)
        #expect(yaml.contains("description:") == false)
    }

    @Test("includes subtitle, publisher, and description when present")
    func includesOptionalFieldsWhenPresent() {
        let metadata = ProjectMetadata(
            title: "The Last Shift",
            subtitle: "A Novel",
            author: "Tim Fleet",
            copyrightYear: 2026,
            publisher: "Acme Books",
            description: "A story about a night shift."
        )
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("subtitle: \"A Novel\""))
        #expect(yaml.contains("publisher: \"Acme Books\""))
        #expect(yaml.contains("description: \"A story about a night shift.\""))
    }

    @Test("escapes embedded quotes so the YAML stays valid")
    func escapesEmbeddedQuotes() {
        let metadata = ProjectMetadata(title: "The \"Last\" Shift", author: "Tim Fleet", copyrightYear: 2026)
        let yaml = EPUBMetadataGenerator.metaYAML(for: metadata, generatedDate: fixedDate)

        #expect(yaml.contains("title: \"The \\\"Last\\\" Shift\""))
    }
}
