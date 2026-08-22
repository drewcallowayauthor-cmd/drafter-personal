import AppKit
import SwiftUI

/// An `NSScrollView` that keeps its document text view wrapped to a fixed character
/// width, centered, via symmetric `textContainerInset` (§8.3 point 2 — this affects
/// daily writing comfort more than any other setting). Soft wrap only; the app must
/// never hard-wrap the underlying text (§4.7) — this column is purely visual.
///
/// When typewriter scrolling is on, the vertical inset also carries the bottom
/// overscroll padding `TypewriterTextView` needs (see its doc comment) — the two
/// concerns share one `textContainerInset` write since AppKit only exposes one.
final class MeasuredColumnScrollView: NSScrollView {
    var measuredWidthInCharacters: Int = 68 {
        didSet { needsLayout = true }
    }
    var isTypewriterScrollingEnabled = true {
        didSet { needsLayout = true }
    }
    var typewriterCaretFraction: CGFloat = 0.45 {
        didSet { needsLayout = true }
    }

    private let minimumMargin: CGFloat = 24
    private let restingVerticalInset: CGFloat = 24
    /// Permanent breathing room above the first line, on top of whatever the overscroll
    /// math below needs — kept as a separate addend to `textContainerInset.height`
    /// rather than baked into `overscrollAmount` itself, since `overscrollAmount` must
    /// stay exactly equal to the *overscroll-only* portion for `textContainerOrigin`'s
    /// cancellation to still land correctly (see `TypewriterTextView`'s doc comment).
    private let topWhitespace: CGFloat = 120

    override func layout() {
        super.layout()
        applyMeasuredInset()
    }

    func applyMeasuredInset() {
        guard let textView = documentView as? TypewriterTextView else { return }
        let available = bounds.width
        let sample = String(repeating: "n", count: measuredWidthInCharacters) as NSString
        let measuredWidth = sample.size(withAttributes: [.font: textView.font ?? .systemFont(ofSize: 15)]).width

        let effectiveWidth = min(measuredWidth, max(available - minimumMargin * 2, 0))
        let horizontalInset = max((available - effectiveWidth) / 2, minimumMargin)

        guard isTypewriterScrollingEnabled else {
            textView.overscrollAmount = 0
            let newInset = NSSize(width: horizontalInset, height: restingVerticalInset)
            if textView.textContainerInset != newInset {
                textView.textContainerInset = newInset
            }
            return
        }

        // Typewriter mode needs the document to always be "tall enough" to pull any
        // line — including the last one — up to the target caret position. Without
        // this, the scroll target for a late line exceeds the document's actual
        // scrollable range, gets clamped, and macOS's elastic bounce animates back.
        //
        // NSTextView reserves `textContainerInset.height` on *both* top and bottom
        // when sizing its frame; TypewriterTextView.textContainerOrigin cancels only
        // the top allocation, so the bottom ends up with `2 × inset` of real overscroll
        // room. What we actually need at the bottom is `(1 - fraction) × visibleHeight`
        // (the gap between the target line position and the natural end of content),
        // so the inset itself is half that, plus a small safety margin.
        let requiredBottomOverscroll = bounds.height * (1 - typewriterCaretFraction)
        let inset = ceil(requiredBottomOverscroll / 2) + 24
        textView.overscrollAmount = inset

        // `textContainerInset.height` carries `topWhitespace` on top of `inset`, but
        // `overscrollAmount` (just above) deliberately doesn't — the mismatch between
        // the two is exactly `topWhitespace` of visible top margin that
        // `textContainerOrigin`'s cancellation leaves behind. It also adds
        // `topWhitespace` of extra (harmless — more than required, never less) room at
        // the bottom, since AppKit reserves this height on both ends of the frame.
        let newInset = NSSize(width: horizontalInset, height: inset + topWhitespace)
        if textView.textContainerInset != newInset {
            textView.textContainerInset = newInset
        }
    }
}

/// `NSTextView` fires its own "scroll the caret into view" pass on every selection
/// change — including once per keystroke while typing — independent of our delegate
/// callback, and competing with it produces visible jumps. Suppressing the built-in
/// pass entirely while typewriter mode is on removes that competition; see
/// `MeasuredColumnScrollView.applyMeasuredInset()` for the overscroll half of the fix.
final class TypewriterTextView: NSTextView {
    var isTypewriterScrollingEnabled = true
    /// Set to exactly `textContainerInset.height` when typewriter mode is on — must
    /// match it exactly, so the cancellation below fully removes the top allocation
    /// rather than leaving a mismatched remainder (the bug an earlier version of this
    /// had: subtracting a different value than the inset itself blew the bottom gap up
    /// to roughly double what was intended).
    var overscrollAmount: CGFloat = 0

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        guard isTypewriterScrollingEnabled else { return origin }
        return NSPoint(x: origin.x, y: origin.y - overscrollAmount)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !isTypewriterScrollingEnabled else { return }
        super.scrollRangeToVisible(range)
    }

    /// ⌘I (§8.3 point 6). `NSApp.sendAction(_:to: nil, from:)` routes this through the
    /// responder chain to whichever view is first responder, so it's a no-op unless
    /// this text view actually has focus.
    @objc func drafterToggleItalic(_ sender: Any?) {
        applyMarkerWrap("*")
    }

    /// ⌘B (§8.3 point 6).
    @objc func drafterToggleBold(_ sender: Any?) {
        applyMarkerWrap("**")
    }

    private func applyMarkerWrap(_ marker: String) {
        let result = MarkerWrapping.wrap(text: string, selectedRange: selectedRange(), marker: marker)
        guard shouldChangeText(in: result.replacementRange, replacementString: result.replacementText) else { return }
        textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacementText)
        didChangeText()
        setSelectedRange(result.newSelectedRange)
    }

    /// Forces a plain-text paste (matching `isRichText = false`, §8.3) and normalizes
    /// line endings via `PastedTextNormalizer` — see its doc comment for why.
    override func paste(_ sender: Any?) {
        guard let pasteboardString = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        let normalized = PastedTextNormalizer.normalize(pasteboardString)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: normalized) else { return }
        textStorage?.replaceCharacters(in: range, with: normalized)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (normalized as NSString).length, length: 0))
    }
}

/// A one-shot "select this range and scroll it into view" request from outside the text
/// view — e.g. project-wide find & replace (§8.3 point 8) jumping to a result. `id`
/// (rather than comparing `range` alone) so requesting the same range twice in a row —
/// re-clicking the same search result — still re-triggers the jump.
struct SceneTextJumpRequest: Equatable {
    let range: NSRange
    let id = UUID()
}

/// M1's `NSTextView` wrapper (§8.3): measured column, soft wrap only, editable, bound to
/// a text binding, with toggleable typewriter scrolling. Syntax affordances and shortcuts
/// are separate slices layered on top.
struct SceneTextView: NSViewRepresentable {
    @Binding var text: String
    var measuredWidthInCharacters: Int = 68
    var isTypewriterScrollingEnabled: Bool = true
    /// Fraction of the visible height the caret is held at (§8.3 point 4's default 45%).
    var typewriterCaretFraction: CGFloat = 0.45
    var fontSize: CGFloat = 15
    var lineHeightMultiple: CGFloat = 1.0
    /// See `SceneTextJumpRequest`. `nil` most of the time; set transiently by the caller.
    var jumpRequest: SceneTextJumpRequest?

    func makeNSView(context: Context) -> MeasuredColumnScrollView {
        let textView = TypewriterTextView()
        textView.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.string = text
        MarkdownSyntaxHighlighter.applyAttributes(to: textView.textStorage!, baseFont: textView.font!, lineHeightMultiple: lineHeightMultiple)

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = MeasuredColumnScrollView()
        scrollView.measuredWidthInCharacters = measuredWidthInCharacters
        scrollView.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        scrollView.typewriterCaretFraction = typewriterCaretFraction
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: MeasuredColumnScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TypewriterTextView else { return }
        let desiredFont = NSFont.systemFont(ofSize: fontSize)
        let fontChanged = textView.font?.pointSize != fontSize
        if textView.string != text {
            textView.string = text
            textView.font = desiredFont
            MarkdownSyntaxHighlighter.applyAttributes(to: textView.textStorage!, baseFont: desiredFont, lineHeightMultiple: lineHeightMultiple)
            // This branch only fires for a wholesale content swap from outside the
            // user's own typing (opening a different scene, an external-change
            // reload, a history restore) — never from the text view's own edits
            // reflecting back through `text` (that round-trip lands here with an
            // already-equal string, above). Undo actions recorded against the old
            // content reference character ranges that no longer mean anything once
            // the content underneath them has changed, so leaving them in place risks
            // ⌘Z replaying a stale edit into whatever scene happens to be open now.
            textView.undoManager?.removeAllActions()
        } else if fontChanged || context.coordinator.lineHeightMultiple != lineHeightMultiple {
            textView.font = desiredFont
            MarkdownSyntaxHighlighter.applyAttributes(to: textView.textStorage!, baseFont: desiredFont, lineHeightMultiple: lineHeightMultiple)
        }
        context.coordinator.lineHeightMultiple = lineHeightMultiple
        scrollView.measuredWidthInCharacters = measuredWidthInCharacters
        scrollView.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        scrollView.typewriterCaretFraction = typewriterCaretFraction
        scrollView.applyMeasuredInset()
        textView.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        context.coordinator.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        context.coordinator.typewriterCaretFraction = typewriterCaretFraction

        if let jumpRequest, jumpRequest.id != context.coordinator.lastAppliedJumpID,
            jumpRequest.range.location + jumpRequest.range.length <= (textView.string as NSString).length
        {
            context.coordinator.lastAppliedJumpID = jumpRequest.id
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(jumpRequest.range)
            textView.scrollRangeToVisible(jumpRequest.range)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text)
        coordinator.isTypewriterScrollingEnabled = isTypewriterScrollingEnabled
        coordinator.typewriterCaretFraction = typewriterCaretFraction
        coordinator.lineHeightMultiple = lineHeightMultiple
        return coordinator
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var isTypewriterScrollingEnabled = true
        var typewriterCaretFraction: CGFloat = 0.45
        var lineHeightMultiple: CGFloat = 1.0
        var lastAppliedJumpID: UUID?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let textStorage = textView.textStorage, let font = textView.font {
                MarkdownSyntaxHighlighter.applyAttributes(to: textStorage, baseFont: font, lineHeightMultiple: lineHeightMultiple)
            }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard isTypewriterScrollingEnabled, let textView = notification.object as? NSTextView else { return }
            scrollToTypewriterPosition(textView: textView)
        }

        /// Holds the caret at a fixed vertical position (default 45% down the visible
        /// area) by scrolling the content underneath it (§8.3 point 4). Bottom
        /// overscroll (`MeasuredColumnScrollView.applyMeasuredInset()`) guarantees this
        /// target is always reachable, even on the document's last line, so there's
        /// nothing left to clamp-and-bounce.
        private func scrollToTypewriterPosition(textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                let container = textView.textContainer,
                let scrollView = textView.enclosingScrollView
            else { return }

            layoutManager.ensureLayout(for: container)

            let numberOfGlyphs = layoutManager.numberOfGlyphs
            guard numberOfGlyphs > 0 else { return }

            let caretLocation = textView.selectedRange().location
            let glyphIndex = min(max(caretLocation, 0), numberOfGlyphs - 1)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerOrigin.y

            let visibleHeight = scrollView.contentView.bounds.height
            let targetY = max(0, lineRect.midY - visibleHeight * typewriterCaretFraction)

            // Setting bounds.origin directly, rather than NSView.scroll(to:), avoids
            // an extra layout/animation pass fighting our own positioning.
            scrollView.contentView.bounds.origin = NSPoint(x: 0, y: targetY)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
