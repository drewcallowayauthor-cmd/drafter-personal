import Foundation

/// Naming and retention for `git bundle` backups (§6.1B). Pure logic, kept separate from
/// the scheduling/subprocess side so it's trivial to unit test.
public enum BundleNaming {
    public static func filename(bookTitle: String, date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return "\(bookTitle)-\(formatter.string(from: date)).bundle"
    }

    /// Given existing bundle filenames (newest sortable last), returns the ones to delete
    /// so at most `retentionCount` remain.
    public static func bundlesToPrune(existing: [String], retentionCount: Int) -> [String] {
        let sorted = existing.sorted()
        guard sorted.count > retentionCount else { return [] }
        return Array(sorted.dropLast(retentionCount))
    }
}
