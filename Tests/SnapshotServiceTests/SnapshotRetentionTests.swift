import Foundation
import Testing
@testable import SnapshotService

@Suite("SnapshotRetention")
struct SnapshotRetentionTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("keeps everything from the last 48 hours untouched")
    func keepsRecentEntriesInFull() {
        let now = Date()
        let entries = (0..<10).map { hoursAgo in
            SnapshotRetention.Entry(name: "h\(hoursAgo)", date: now.addingTimeInterval(-Double(hoursAgo) * 3600), isProtected: false)
        }
        #expect(SnapshotRetention.namesToPrune(entries: entries, now: now, calendar: utc).isEmpty)
    }

    @Test("beyond 48 hours, keeps only the newest entry per calendar day")
    func thinsToOnePerDay() {
        let now = utc.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        // Three entries on the same day, 5 days ago (well past the 48h cutoff).
        let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!
        let entries = [
            SnapshotRetention.Entry(name: "morning", date: day.addingTimeInterval(8 * 3600), isProtected: false),
            SnapshotRetention.Entry(name: "noon", date: day.addingTimeInterval(12 * 3600), isProtected: false),
            SnapshotRetention.Entry(name: "evening", date: day.addingTimeInterval(20 * 3600), isProtected: false)
        ]

        let pruned = Set(SnapshotRetention.namesToPrune(entries: entries, now: now, calendar: utc))

        #expect(pruned == ["morning", "noon"])
    }

    @Test("beyond 30 days, keeps only the newest entry per calendar week")
    func thinsToOnePerWeek() {
        let now = utc.date(from: DateComponents(year: 2026, month: 8, day: 18))!
        let old = utc.date(from: DateComponents(year: 2026, month: 5, day: 4))! // ~15 weeks back
        let entries = [
            SnapshotRetention.Entry(name: "monday", date: old, isProtected: false),
            SnapshotRetention.Entry(name: "tuesday", date: old.addingTimeInterval(24 * 3600), isProtected: false)
        ]

        let pruned = SnapshotRetention.namesToPrune(entries: entries, now: now, calendar: utc)

        #expect(pruned == ["monday"])
    }

    @Test("a protected entry survives even when it's the oldest in a week bucket that also gets thinned")
    func protectedEntriesSurvive() {
        let now = Date()
        let ancient = now.addingTimeInterval(-400 * 24 * 3600)
        let entries = [
            // Protected, and older than both unprotected entries below — if protection
            // worked merely by being "the newest kept per bucket," this would be the
            // one pruned. It must survive regardless.
            SnapshotRetention.Entry(name: "checkpoint", date: ancient, isProtected: true),
            SnapshotRetention.Entry(name: "autosave-newer", date: ancient.addingTimeInterval(2 * 3600), isProtected: false),
            SnapshotRetention.Entry(name: "autosave-older", date: ancient.addingTimeInterval(1 * 3600), isProtected: false)
        ]

        let pruned = SnapshotRetention.namesToPrune(entries: entries, now: now, calendar: utc)

        #expect(pruned == ["autosave-older"])
    }
}
