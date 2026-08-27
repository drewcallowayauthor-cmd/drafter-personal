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
                .font(Theme.Font.heading(15))
                .foregroundStyle(Theme.Color.text)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(totals.project) words")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    if targetWords > 0 {
                        Text("of \(targetWords)")
                            .font(Theme.Font.body(11))
                            .foregroundStyle(Theme.Color.textMuted)
                    }
                }
                if targetWords > 0 {
                    ProgressView(value: Double(totals.project), total: Double(targetWords))
                        .tint(Theme.Color.accent)
                }
            }

            if sessionWords != 0 {
                Text(sessionWords > 0 ? "+\(sessionWords) this session" : "\(sessionWords) this session")
                    .font(Theme.Font.body(11))
                    .foregroundStyle(Theme.Color.textMuted)
            }

            if !totals.perChapter.isEmpty {
                Rectangle().fill(Theme.Color.divider).frame(height: 1)
                // Bounded + scrollable: a 30–50 chapter project would otherwise push
                // this list past the panel's height and squeeze the History section
                // (and any progress bar above) off screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(totals.perChapter, id: \.chapter) { entry in
                            HStack {
                                Text(entry.chapter)
                                    .font(Theme.Font.body(11))
                                    .foregroundStyle(Theme.Color.text)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.words)")
                                    .font(Theme.Font.body(11))
                                    .foregroundStyle(Theme.Color.neutral500)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
    }
}
