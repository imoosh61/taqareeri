import Foundation

/// Spelling & grammar correction of the whole report through Claude, applied word by word so
/// formatting and page breaks are kept. Long reports are sent in parts.
@MainActor
struct ProofreadService {
    private let maxChunkLength = 3500

    func proofread(
        _ text: NSAttributedString,
        context: AIReportContext,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> (NSAttributedString, Int) {
        let chunks = chunkRanges(text.string as NSString)
        var replacements: [(NSRange, NSAttributedString)] = []
        var totalChanges = 0

        for (index, range) in chunks.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, chunks.count)

            let original = text.attributedSubstring(from: range)
            let corrected = try await AIWritingService().run(task: .proofread, input: original.string, context: context, raw: true)
            try Task.checkCancellation()

            // Ignore suspicious answers (e.g. truncated output) instead of losing text.
            guard corrected.count >= original.string.trimmed.count / 2 else { continue }

            let (updated, changes) = TextDiff.apply(corrected: corrected, to: original)
            if changes > 0 {
                replacements.append((range, updated))
                totalChanges += changes
            }
        }

        let result = NSMutableAttributedString(attributedString: text)
        for (range, updated) in replacements.reversed() {
            result.replaceCharacters(in: range, with: updated)
        }
        return (result, totalChanges)
    }

    /// Ranges of non-empty text between page breaks, split at line ends when longer than the limit.
    /// Surrounding whitespace is excluded so it is never altered.
    private func chunkRanges(_ string: NSString) -> [NSRange] {
        var raw: [NSRange] = []
        var start = 0
        for index in 0..<string.length {
            let character = string.character(at: index)
            if character == BodyDocument.pageBreakUnit || (character == 0x0A && index - start >= maxChunkLength) {
                raw.append(NSRange(location: start, length: index - start))
                start = index + 1
            }
        }
        raw.append(NSRange(location: start, length: string.length - start))

        let whitespace = CharacterSet.whitespacesAndNewlines
        return raw.compactMap { range in
            var lower = range.location
            var upper = NSMaxRange(range)
            while lower < upper, let scalar = UnicodeScalar(string.character(at: lower)), whitespace.contains(scalar) { lower += 1 }
            while upper > lower, let scalar = UnicodeScalar(string.character(at: upper - 1)), whitespace.contains(scalar) { upper -= 1 }
            return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
        }
    }
}
