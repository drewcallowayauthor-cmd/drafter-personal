import Foundation

/// Appendix B's `History/` folder naming: `<local ISO 8601-ish timestamp, colon-safe>
/// <machine name>`. Colon-safe because `:` isn't legal in a Finder filename (it's the
/// classic-Mac path separator HFS+/APFS still special-case), so `HH-mm-ss` stands in
/// for `HH:mm:ss`.
enum SnapshotFolderName {
    private static let dateFormat = "yyyy-MM-dd HH-mm-ss"
    /// `"yyyy-MM-dd HH-mm-ss"` is exactly 19 characters; the machine name follows a
    /// single separating space.
    private static let timestampLength = 19

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = dateFormat
        formatter.timeZone = calendar.timeZone
        return formatter
    }

    static func make(date: Date, machine: String, calendar: Calendar = .current) -> String {
        "\(formatter(calendar: calendar).string(from: date)) \(machine)"
    }

    /// `nil` for anything that isn't one of this app's snapshot folders — e.g. a stray
    /// file a cloud client dropped into `History/`.
    static func parse(_ name: String, calendar: Calendar = .current) -> (date: Date, machine: String)? {
        guard name.count > timestampLength + 1 else { return nil }
        let timestampEnd = name.index(name.startIndex, offsetBy: timestampLength)
        let dateString = String(name[name.startIndex..<timestampEnd])
        let machine = String(name[name.index(after: timestampEnd)...])
        guard let date = formatter(calendar: calendar).date(from: dateString) else { return nil }
        return (date, machine)
    }
}
