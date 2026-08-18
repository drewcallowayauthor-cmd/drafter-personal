import SwiftUI

/// §5.8's two-pane diff with word-level highlighting: old on the left, new on the
/// right, sharing one scroll so corresponding paragraphs line up. Purely a renderer for
/// `SceneDiff`'s output — no diffing logic lives here.
struct DiffView: View {
    let lines: [SceneDiffLine]
    let oldLabel: String
    let newLabel: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(oldLabel).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text(newLabel).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Divider()

            if lines.isEmpty {
                ContentUnavailableView("No Differences", systemImage: "checkmark.circle")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 16) {
                                column(text: line.oldText, words: line.oldWords, kind: line.kind, isOldSide: true)
                                column(text: line.newText, words: line.newWords, kind: line.kind, isOldSide: false)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 700)
    }

    @ViewBuilder
    private func column(text: String?, words: [DiffOp<String>]?, kind: SceneDiffLine.Kind, isOldSide: Bool) -> some View {
        Group {
            if let words {
                wordText(words)
            } else if let text {
                Text(text.isEmpty ? " " : text)
            } else {
                Text(" ")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background(backgroundColor(for: kind, isOldSide: isOldSide))
        .cornerRadius(4)
    }

    private func wordText(_ words: [DiffOp<String>]) -> Text {
        words.reduce(Text("")) { partial, op in
            switch op {
            case .equal(let word):
                return partial + Text(word)
            case .delete(let word):
                return partial + Text(word).foregroundColor(.red).strikethrough()
            case .insert(let word):
                return partial + Text(word).foregroundColor(.green)
            }
        }
    }

    private func backgroundColor(for kind: SceneDiffLine.Kind, isOldSide: Bool) -> Color {
        switch kind {
        case .removed: return isOldSide ? .red.opacity(0.15) : .clear
        case .added: return isOldSide ? .clear : .green.opacity(0.15)
        case .modified: return .yellow.opacity(0.08)
        case .unchanged: return .clear
        }
    }
}
