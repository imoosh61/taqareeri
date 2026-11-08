import Foundation

/// Safe, local clean-up of Arabic text: spacing and punctuation only (no word changes except
/// attaching a detached conjunction "و"). Works in place on attributed text, so bold, underline,
/// sizes and alignment are preserved.
enum ArabicTextFormatter {
    private struct Rule {
        let regex: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String) {
            // Patterns are constants; a failure here is a programming error caught on first launch.
            regex = try! NSRegularExpression(pattern: pattern, options: [])
            self.template = template
        }
    }

    private static let rules: [Rule] = [
        // Latin punctuation written after Arabic words → Arabic punctuation
        Rule(#"(?<=\p{Arabic})[ \t]*,"#, "،"),
        Rule(#"(?<=\p{Arabic})[ \t]*;"#, "؛"),
        Rule(#"(?<=\p{Arabic})[ \t]*\?"#, "؟"),
        // Repeated commas / semicolons
        Rule(#"([،؛])(?:[ \t]*\1)+"#, "$1"),
        // No space before punctuation or closing brackets
        Rule(#"[ \t]+(?=[،؛؟!:.\)\]»])"#, ""),
        // No space after opening brackets
        Rule(#"(?<=[\(\[«])[ \t]+"#, ""),
        // One space after punctuation when an Arabic word follows directly
        Rule(#"([،؛؟!:.])(?=\p{Arabic})"#, "$1 "),
        // Space before an opening bracket that sticks to a previous Arabic word
        Rule(#"(?<=\p{Arabic})(?=[\(«])"#, " "),
        // Attach the conjunction و to the next word (only between real words)
        Rule(#"(?<=\p{Arabic}{2}[ \t])و[ \t]+(?=\p{Arabic}{2})"#, "و"),
        Rule(#"(?m)^و[ \t]+(?=\p{Arabic}{2})"#, "و"),
        // Collapse repeated spaces / tabs
        Rule(#"[ \t]{2,}"#, " "),
        // Trim spaces at the start and end of lines
        Rule(#"(?m)^[ \t]+|[ \t]+$"#, ""),
        // At most one empty line between paragraphs
        Rule(#"\n{3,}"#, "\n\n")
    ]

    /// Applies all rules; returns the number of edits made.
    @discardableResult
    static func format(_ text: NSMutableAttributedString) -> Int {
        var edits = 0
        for rule in rules {
            let string = text.string as NSString
            let matches = rule.regex.matches(in: text.string, options: [], range: NSRange(location: 0, length: string.length))
            for match in matches.reversed() {
                let replacement = rule.regex.replacementString(for: match, in: text.string, offset: 0, template: rule.template)
                if replacement != string.substring(with: match.range) {
                    text.replaceCharacters(in: match.range, with: replacement)
                    edits += 1
                }
            }
        }
        return edits
    }
}

/// Applies a corrected version of a text to the original attributed text word by word,
/// so only changed words are replaced and all formatting on unchanged words survives.
enum TextDiff {
    private static let tokenizer = try! NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{M}\p{N}]*|\p{N}+|\s+|."#,
        options: [.dotMatchesLineSeparators]
    )

    static func tokenRanges(_ string: NSString) -> [NSRange] {
        tokenizer.matches(in: string as String, options: [], range: NSRange(location: 0, length: string.length)).map(\.range)
    }

    /// Returns the updated text and the number of changed words.
    static func apply(corrected: String, to original: NSAttributedString) -> (NSAttributedString, Int) {
        let source = original.string as NSString
        let ranges = tokenRanges(source)
        let oldTokens = ranges.map { source.substring(with: $0) }
        let target = corrected as NSString
        let newTokens = tokenRanges(target).map { target.substring(with: $0) }

        let difference = newTokens.difference(from: oldTokens)
        guard !difference.isEmpty else { return (original, 0) }

        var pieces = ranges.map { original.attributedSubstring(from: $0) }
        let fallback: [NSAttributedString.Key: Any] = original.length > 0
            ? original.attributes(at: 0, effectiveRange: nil) : [:]
        var removedWords = 0
        var insertedWords = 0

        for change in difference.removals.reversed() {
            if case let .remove(offset, element, _) = change {
                pieces.remove(at: offset)
                if isWord(element) { removedWords += 1 }
            }
        }
        for change in difference.insertions {
            if case let .insert(offset, element, _) = change {
                let neighbor = offset > 0 ? pieces[offset - 1] : pieces.first
                let attributes = neighbor.flatMap { $0.length > 0 ? $0.attributes(at: $0.length - 1, effectiveRange: nil) : nil } ?? fallback
                pieces.insert(NSAttributedString(string: element, attributes: attributes), at: offset)
                if isWord(element) { insertedWords += 1 }
            }
        }

        let result = NSMutableAttributedString()
        pieces.forEach(result.append)
        return (result, max(removedWords, insertedWords))
    }

    private static func isWord(_ token: String) -> Bool {
        token.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }
}
