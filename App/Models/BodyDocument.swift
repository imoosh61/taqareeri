import Foundation

/// Storage-friendly representation of the report body.
/// Ranges are expressed in UTF-16 units (NSString indexing) so they map 1:1 to NSAttributedString.
/// Page breaks are stored as U+000C (form feed) characters inside `text`.
struct BodyDocument: Codable, Equatable {
    struct Run: Codable, Equatable {
        var location: Int
        var length: Int
        var bold: Bool
        var underline: Bool
        var size: Double
    }

    struct Paragraph: Codable, Equatable {
        var location: Int
        var length: Int
        var alignment: ParagraphAlignment
    }

    static let pageBreak = "\u{000C}"
    static let pageBreakUnit: unichar = 0x0C

    var text = ""
    var runs: [Run] = []
    var paragraphs: [Paragraph] = []

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func shiftSizes(by delta: Double) {
        guard delta != 0 else { return }
        for index in runs.indices {
            runs[index].size = min(max(runs[index].size + delta, 8), 72)
        }
    }

    mutating func setAllAlignments(_ alignment: ParagraphAlignment) {
        for index in paragraphs.indices {
            paragraphs[index].alignment = alignment
        }
    }
}
