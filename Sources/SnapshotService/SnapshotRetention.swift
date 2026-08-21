import Foundation

/// Pure retention-thinning logic for §7.3, kept separate from any filesystem access so
/// it's trivial to unit test. Time Machine–style: keep everything recent, then thin to
/// one-per-day, then one-per-week, and never touch a protected (checkpoint/pre-export)
/// entry regardless of age.
public enum SnapshotRetention {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let date: Date
        public let isProtected: Bool

        public init(name: String, date: Date, isProtected: Bool) {
            self.name = name
            self.date = date
            self.isProtected = isProtected
        }
    }

    /// Returns the names to delete so `entries` matches §7.3's schedule: everything
    /// from the last 48 hours kept in full; one per calendar day for the 30 days
    /// before that; one per calendar week beyond that; protected entries always kept.
    public static func namesToPrune(
        entries: [Entry],
        now: Date,
        calendar: Calendar = .current
    ) -> [String] {
        let recentCutoff = now.addingTimeInterval(-48 * 3600)
        let dailyCutoff = now.addingTimeInterval(-30 * 24 * 3600)

        // Newest first, so the first entry seen in each bucket — the one kept — is
        // always the most recent one in that bucket.
        let sorted = entries.sorted { $0.date > $1.date }

        var keep = Set<String>()
        var seenDayBuckets = Set<DateComponents>()
        var seenWeekBuckets = Set<DateComponents>()

        for entry in sorted {
            if entry.isProtected || entry.date >= recentCutoff {
                keep.insert(entry.name)
                continue
            }
            if entry.date >= dailyCutoff {
                let bucket = calendar.dateComponents([.year, .month, .day], from: entry.date)
                if seenDayBuckets.insert(bucket).inserted {
                    keep.insert(entry.name)
                }
                continue
            }
            let bucket = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
            if seenWeekBuckets.insert(bucket).inserted {
                keep.insert(entry.name)
            }
        }

        return entries.filter { !keep.contains($0.name) }.map(\.name)
    }
}
