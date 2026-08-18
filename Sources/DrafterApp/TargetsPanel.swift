import CompileService
import SwiftUI

/// §8.4's Targets section: session words, and project/chapter totals against
/// `project.json`'s `target.words`, with a progress bar.
struct TargetsPanel: View {
    let totals: WordCountTotals
    let targetWords: Int
    let sessionWords: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Targets")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(totals.project) words")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if targetWords > 0 {
                        Text("of \(targetWords)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if targetWords > 0 {
                    ProgressView(value: Double(totals.project), total: Double(targetWords))
                }
            }

            if sessionWords != 0 {
                Text(sessionWords > 0 ? "+\(sessionWords) this session" : "\(sessionWords) this session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !totals.perChapter.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(totals.perChapter, id: \.chapter) { entry in
                        HStack {
                            Text(entry.chapter)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.words)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
