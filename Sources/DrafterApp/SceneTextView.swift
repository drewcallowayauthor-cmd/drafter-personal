import AppKit
import SwiftUI

/// An `NSScrollView` that keeps its document text view wrapped to a fixed character
/// width, centered, via symmetric `textContainerInset` (§8.3 point 2 — this affects
/// daily writing comfort more than any other setting). Soft wrap only; the app must
/// never hard-wrap the underlying text (§4.7) — this column is purely visual.
final class MeasuredColumnScrollView: NSScrollView {
    var measuredWidthInCharacters: Int = 68 {
        didSet { needsLayout = true }
    }

    private let minimumMargin: CGFloat = 24
    private let verticalInset: CGFloat = 24

    override func layout() {
        super.layout()
        applyMeasuredInset()
    }

    func applyMeasuredInset() {
        guard let textView = documentView as? NSTextView else { return }
        let available = bounds.width
        let sample = String(repeating: "n", count: measuredWidthInCharacters) as NSString
        let measuredWidth = sample.size(withAttributes: [.font: textView.font ?? .systemFont(ofSize: 15)]).width

        let effectiveWidth = min(measuredWidth, max(available - minimumMargin * 2, 0))
        let horizontalInset = max((available - effectiveWidth) / 2, minimumMargin)

        let newInset = NSSize(width: horizontalInset, height: verticalInset)
        if textView.textContainerInset != newInset {
            textView.textContainerInset = newInset
        }
    }
}

/// M1's `NSTextView` wrapper (§8.3): measured column, soft wrap only, editable, bound to
/// a text binding. Typewriter scrolling, syntax affordances, and shortcuts are separate
/// slices layered on top.
struct SceneTextView: NSViewRepresentable {
    @Binding var text: String
    var measuredWidthInCharacters: Int = 68

    func makeNSView(context: Context) -> MeasuredColumnScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = .systemFont(ofSize: 15)
        textView.string = text

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = MeasuredColumnScrollView()
        scrollView.measuredWidthInCharacters = measuredWidthInCharacters
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: MeasuredColumnScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        scrollView.measuredWidthInCharacters = measuredWidthInCharacters
        scrollView.applyMeasuredInset()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
