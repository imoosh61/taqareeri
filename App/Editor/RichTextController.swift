import UIKit

/// Bridges SwiftUI toolbar actions to the UIKit text view (selection-based formatting).
@MainActor
final class RichTextController {
    private(set) weak var textView: UITextView?

    var settingsProvider: () -> TextStyleSettings = { TextStyleSettings() }
    var onTextChanged: (NSAttributedString) -> Void = { _ in }
    var onSelectionChanged: (Int) -> Void = { _ in }
    /// Set by the on-page editor: switches between fit-width and reading zoom.
    var zoomToggle: (() -> Void)?

    func attach(_ textView: UITextView) {
        if self.textView !== textView { self.textView = textView }
    }

    // MARK: - Delegate forwarding

    func textDidChange(_ textView: UITextView) {
        onTextChanged(textView.attributedText)
    }

    func selectionDidChange(_ textView: UITextView) {
        let location = textView.selectedRange.location
        // Deferred: selection changes can fire during a SwiftUI view update.
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChanged(location)
        }
    }

    // MARK: - Character formatting

    func toggleBold() {
        guard let textView else { return }
        let settings = settingsProvider()
        let range = textView.selectedRange

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let current = (attributes[.font] as? UIFont) ?? BodyStyler.baseFont(settings)
            attributes[.font] = BodyStyler.font(name: settings.fontName, size: current.pointSize, bold: !current.isBold)
            textView.typingAttributes = attributes
            return
        }

        var allBold = true
        textView.textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            if !((value as? UIFont)?.isBold ?? false) {
                allBold = false
                stop.pointee = true
            }
        }
        mutate(textView) { storage in
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let size = (value as? UIFont)?.pointSize ?? CGFloat(settings.fontSize)
                storage.addAttribute(.font, value: BodyStyler.font(name: settings.fontName, size: size, bold: !allBold), range: subrange)
            }
        }
    }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let underlined = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            attributes[.underlineStyle] = underlined ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attributes
            return
        }

        var allUnderlined = true
        textView.textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            if ((value as? Int) ?? 0) == 0 {
                allUnderlined = false
                stop.pointee = true
            }
        }
        mutate(textView) { storage in
            if allUnderlined {
                storage.removeAttribute(.underlineStyle, range: range)
            } else {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
    }

    func adjustSelectionSize(by delta: CGFloat) {
        guard let textView else { return }
        let settings = settingsProvider()
        let range = textView.selectedRange

        func resized(_ font: UIFont?) -> UIFont {
            let base = font ?? BodyStyler.baseFont(settings)
            let size = min(max(base.pointSize + delta, 8), 72)
            return BodyStyler.font(name: settings.fontName, size: size, bold: base.isBold)
        }

        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.font] = resized(attributes[.font] as? UIFont)
            textView.typingAttributes = attributes
            return
        }
        mutate(textView) { storage in
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                storage.addAttribute(.font, value: resized(value as? UIFont), range: subrange)
            }
            BodyStyler.normalizeParagraphStyles(storage, in: range, settings: settings)
        }
    }

    // MARK: - Paragraph formatting

    func setAlignment(_ alignment: ParagraphAlignment) {
        guard let textView else { return }
        let settings = settingsProvider()
        let text = textView.textStorage.string as NSString
        let paragraphRange = text.paragraphRange(for: textView.selectedRange)

        var typing = textView.typingAttributes
        typing[.paragraphStyle] = BodyStyler.paragraphStyle(alignment, settings: settings)
        defer { textView.typingAttributes = typing }

        guard paragraphRange.length > 0 else { return }
        mutate(textView) { storage in
            storage.addAttribute(.paragraphStyle, value: BodyStyler.paragraphStyle(alignment, settings: settings), range: paragraphRange)
            BodyStyler.normalizeParagraphStyles(storage, in: paragraphRange, settings: settings)
        }
    }

    // MARK: - Text access (AI assistant)

    var selectedText: String {
        guard let textView, textView.selectedRange.length > 0 else { return "" }
        return (textView.textStorage.string as NSString).substring(with: textView.selectedRange)
    }

    var hasSelection: Bool { (textView?.selectedRange.length ?? 0) > 0 }

    /// Replaces the current selection (or inserts at the cursor) with plain text in the current style.
    func replaceSelection(with string: String) {
        insertText(string)
    }

    /// Replaces the whole body with plain text in the base style.
    func replaceAll(with string: String) {
        guard let textView else { return }
        let attributes = BodyStyler.typingAttributes(settingsProvider())
        let replacement = NSAttributedString(string: string, attributes: attributes)
        textView.textStorage.setAttributedString(replacement)
        textView.selectedRange = NSRange(location: replacement.length, length: 0)
        onTextChanged(textView.attributedText)
        onSelectionChanged(textView.selectedRange.location)
    }

    // MARK: - Insertion

    func insertText(_ string: String) {
        guard let textView, !string.isEmpty else { return }
        let range = textView.selectedRange
        var attributes = textView.typingAttributes
        if attributes[.font] == nil {
            attributes = BodyStyler.typingAttributes(settingsProvider())
        }
        let inserted = NSAttributedString(string: string, attributes: attributes)
        textView.textStorage.replaceCharacters(in: range, with: inserted)
        textView.selectedRange = NSRange(location: range.location + inserted.length, length: 0)
        onTextChanged(textView.attributedText)
        onSelectionChanged(textView.selectedRange.location)
    }

    /// Inserts a forced page break. Content after it always starts on a new A4 page.
    func insertPageBreak() {
        guard let textView else { return }
        let text = textView.textStorage.string as NSString
        let location = textView.selectedRange.location
        var atLineStart = location == 0
        if location > 0 {
            let previous = text.character(at: location - 1)
            atLineStart = previous == 0x0A || previous == BodyDocument.pageBreakUnit
        }
        insertText(atLineStart ? BodyDocument.pageBreak : "\n" + BodyDocument.pageBreak)
    }

    // MARK: - Helpers

    private func mutate(_ textView: UITextView, _ change: (NSTextStorage) -> Void) {
        let selection = textView.selectedRange
        let storage = textView.textStorage
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        textView.selectedRange = selection
        onTextChanged(textView.attributedText)
    }
}
