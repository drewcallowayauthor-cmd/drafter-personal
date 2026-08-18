import Foundation
import Testing
@testable import BackupService

@Suite("BundleNaming")
struct BundleNamingTests {
    @Test("formats bundle filename with title and date")
    func formatsFilename() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 8, day: 17)
        let date = utc.date(from: components)!

        let name = BundleNaming.filename(bookTitle: "The Last Shift", date: date, calendar: utc)

        #expect(name == "The Last Shift-2026-08-17.bundle")
    }

    @Test("keeps only the most recent retentionCount bundles")
    func prunesOldestFirst() {
        let existing = [
            "Book-2026-08-01.bundle",
            "Book-2026-08-08.bundle",
            "Book-2026-08-15.bundle",
            "Book-2026-08-17.bundle"
        ]

        let toPrune = BundleNaming.bundlesToPrune(existing: existing, retentionCount: 2)

        #expect(toPrune == ["Book-2026-08-01.bundle", "Book-2026-08-08.bundle"])
    }

    @Test("prunes nothing when under the retention count")
    func prunesNothingWhenUnderLimit() {
        let existing = ["Book-2026-08-15.bundle", "Book-2026-08-17.bundle"]
        #expect(BundleNaming.bundlesToPrune(existing: existing, retentionCount: 8).isEmpty)
    }
}
