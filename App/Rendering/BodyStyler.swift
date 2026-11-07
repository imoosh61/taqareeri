import UIKit

/// Builds attributed text from `BodyDocument` + style settings, and converts back.
/// The font family is global (from settings); runs only carry size / bold / underline,
/// which keeps changing the report font a lossless operation.
enum BodyStyler {
    static func font(name: String, size: CGFloat, bold: Bool) -> UIFont {
        let regular = UIFont(name: name, size: size)
            ?? UIFont(name: FontCatalog.defaultFontName, size: size)
            ?? UIFont.systemFont(ofSize: size)

        // Variable fonts: pick the weight on the "wght" axis (400 regular, 700 bold).
        if regular.isVariable {
            return regular.withVariationWeight(bold ? 700 : 400)
        }
        guard bold else { return regular }

        // 1) Conventional naming: Family-Regular → Family-Bold
        if regular.fontName.hasSuffix("-Regular") {
            let boldName = regular.fontName.replacingOccurrences(of: "-Regular", with: "-Bold")
            if let font = UIFont(name: boldName, size: size) { return font }
        }
        // 2) Same family with the bold trait
        let traits = regular.fontDescriptor.symbolicTraits.union(.traitBold)
        if let descriptor = regular.fontDescriptor.withSymbolicTraits(traits) {
            let font = UIFont(descriptor: descriptor, size: size)
            if font.familyName == regular.familyName { return font }
        }
        // 3) Family has no bold face: keep the regular face
        return regular
    }

    static func baseFont(_ settings: TextStyleSettings) -> UIFont {
        font(name: settings.fontName, size: CGFloat(settings.fontSize), bold: false)
    }

    static func paragraphStyle(_ alignment: ParagraphAlignment, settings: TextStyleSettings) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment.nsAlignment
        style.baseWritingDirection = .rightToLeft
        style.lineHeightMultiple = CGFloat(settings.lineHeightMultiple)
        style.paragraphSpacing = CGFloat(settings.paragraphSpacing)
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func typingAttributes(_ settings: TextStyleSettings) -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont(settings),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle(settings.defaultAlignment, settings: settings)
        ]
    }

    static func attributedString(from document: BodyDocument, settings: TextStyleSettings) -> NSAttributedString {
        let result = NSMutableAttributedString(string: document.text, attributes: typingAttributes(settings))
        let length = result.length
        guard length > 0 else { return result }

        for run in document.runs {
            guard let range = clamped(run.location, run.length, length) else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(name: settings.fontName, size: CGFloat(run.size), bold: run.bold)
            ]
            if run.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            result.addAttributes(attributes, range: range)
        }

        for paragraph in document.paragraphs {
            guard let range = clamped(paragraph.location, paragraph.length, length) else { continue }
            result.addAttribute(.paragraphStyle, value: paragraphStyle(paragraph.alignment, settings: settings), range: range)
        }
        return result
    }

    static func document(from text: NSAttributedString, settings: TextStyleSettings) -> BodyDocument {
        var document = BodyDocument()
        document.text = text.string
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return document }

        var runs: [BodyDocument.Run] = []
        text.enumerateAttributes(in: full, options: []) { attributes, range, _ in
            let font = attributes[.font] as? UIFont
            let bold = font?.isBold ?? false
            let underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            let size = Double(font?.pointSize ?? CGFloat(settings.fontSize))
            if let last = runs.last,
               last.bold == bold, last.underline == underline, last.size == size,
               last.location + last.length == range.location {
                runs[runs.count - 1].length += range.length
            } else {
                runs.append(.init(location: range.location, length: range.length, bold: bold, underline: underline, size: size))
            }
        }

        var paragraphs: [BodyDocument.Paragraph] = []
        text.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, range, _ in
            let alignment = (value as? NSParagraphStyle).map { ParagraphAlignment(nsAlignment: $0.alignment) } ?? settings.defaultAlignment
            if let last = paragraphs.last, last.alignment == alignment, last.location + last.length == range.location {
                paragraphs[paragraphs.count - 1].length += range.length
            } else {
                paragraphs.append(.init(location: range.location, length: range.length, alignment: alignment))
            }
        }

        document.runs = runs
        document.paragraphs = paragraphs
        return document
    }

    /// Re-applies new settings to existing text, shifting relative sizes and (optionally) alignment.
    static func restyle(_ text: NSAttributedString, from old: TextStyleSettings, to new: TextStyleSettings) -> NSAttributedString {
        var doc = BodyStyler.document(from: text, settings: old)
        doc.shiftSizes(by: new.fontSize - old.fontSize)
        if new.defaultAlignment != old.defaultAlignment {
            doc.setAllAlignments(new.defaultAlignment)
        }
        return attributedString(from: doc, settings: new)
    }

    private static func clamped(_ location: Int, _ length: Int, _ total: Int) -> NSRange? {
        guard location >= 0, location < total, length > 0 else { return nil }
        return NSRange(location: location, length: min(length, total - location))
    }
}
