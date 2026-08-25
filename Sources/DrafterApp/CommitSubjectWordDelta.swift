import Foundation

/// Pulls the word delta back out of a commit subject built by `CommitMessageBuilder`
/// (§5.4's `autosave — 3 files, +412 words` / `session end — +1,840 words`) for §5.8's
/// History panel. `checkpoint` and `pre-export` subjects carry no word count and
/// correctly parse to `nil` — the UI shows nothing for those rather than a stray zero.
public enum CommitSubjectWordDelta {
    // swiftlint:disable:next force_try
    private static let pattern = try! NSRegularExpression(pattern: "([+-])([\\d,]+) words?")

    public static func parse(_ subject: String) -> Int? {
        let range = NSRange(subject.startIndex..., in: subject)
        guard let match = pattern.firstMatch(in: subject, range: range),
            let signRange = Range(match.range(at: 1), in: subject),
            let digitsRange = Range(match.range(at: 2), in: subject)
        else {
            return nil
        }

        let digits = subject[digitsRange].replacingOccurrences(of: ",", with: "")
        guard let magnitude = Int(digits) else { return nil }
        return subject[signRange] == "-" ? -magnitude : magnitude
    }
}
