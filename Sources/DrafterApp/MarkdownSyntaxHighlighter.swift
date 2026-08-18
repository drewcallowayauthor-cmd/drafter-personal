import AppKit

/// Paints `MarkdownSyntaxScanner`'s ranges onto an `NSTextStorage` via attributes only
/// (§8.3 point 5) — never inserts or removes characters, so it never moves the caret or
/// disturbs undo. Keeps the file honest (what's on disk is exactly what's in the editor)
/// and costs a fraction of a real rich-text engine.
///
/// Rescans and re-attributes the *entire* string on every call. Fine at the scene
/// lengths this app targets, but a full-document restyle on every keystroke is the
/// first thing to revisit if very long scenes (§12.2's >20k-word case) show hitching —
/// the fix would be scoping the rescan to the edited paragraph instead of the whole text.
public enum MarkdownSyntaxHighlighter {
    public static func applyAttributes(to textStorage: NSTextStorage, baseFont: NSFont) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return }

        let fontManager = NSFontManager.shared
        let italicFont = fontManager.convert(baseFont, toHaveTrait: .italicFontMask)
        let boldFont = fontManager.convert(baseFont, toHaveTrait: .boldFontMask)
        let dimmedColor = NSColor.tertiaryLabelColor

        textStorage.beginEditing()
        textStorage.setAttributes([.font: baseFont, .foregroundColor: NSColor.textColor], range: fullRange)

        for syntaxRange in MarkdownSyntaxScanner.scan(text) {
            switch syntaxRange.kind {
            case .boldMarker, .italicMarker, .headerMarker:
                textStorage.addAttribute(.foregroundColor, value: dimmedColor, range: syntaxRange.range)
            case .boldContent, .headerContent:
                textStorage.addAttribute(.font, value: boldFont, range: syntaxRange.range)
            case .italicContent:
                textStorage.addAttribute(.font, value: italicFont, range: syntaxRange.range)
            }
        }

        textStorage.endEditing()
    }
}
