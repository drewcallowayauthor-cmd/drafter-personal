import Foundation
import Testing
@testable import SnapshotService

@Suite("SnapshotFolderName")
struct SnapshotFolderNameTests {
    @Test("formats and parses round-trip exactly (Appendix B's example shape)")
    func roundTrips() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 14, minute: 32, second: 5))!

        let name = SnapshotFolderName.make(date: date, machine: "Drew-MacBook-Pro", calendar: utc)
        #expect(name == "2026-08-18 14-32-05 Drew-MacBook-Pro")

        let parsed = SnapshotFolderName.parse(name, calendar: utc)
        #expect(parsed?.machine == "Drew-MacBook-Pro")
        #expect(parsed?.date == date)
    }

    @Test("a machine name containing spaces is preserved whole")
    func machineNameWithSpaces() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let name = SnapshotFolderName.make(date: date, machine: "Drew's Mac Studio", calendar: utc)
        #expect(SnapshotFolderName.parse(name, calendar: utc)?.machine == "Drew's Mac Studio")
    }

    @Test("a stray non-snapshot folder name doesn't parse")
    func unrelatedFolderDoesNotParse() {
        #expect(SnapshotFolderName.parse("Resources") == nil)
        #expect(SnapshotFolderName.parse("2026-08-18") == nil)
    }
}
