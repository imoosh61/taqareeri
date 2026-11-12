import CoreGraphics
import Foundation

/// A free text box placed anywhere on a page (notes, stamps of text, extra headings…).
/// It sits on top of the page and does not push the report text.
struct TextBox: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    /// Body page index (0 = first page).
    var page = 0
    /// Position & size in A4 points.
    var rect = CGRect(x: 197, y: 360, width: 200, height: 60)
    var fontSize: Double = 14
    var bold = false
    var alignment: ParagraphAlignment = .center
    var showBorder = false
    var colorHex = "000000"

    static let minimumSize = CGSize(width: 50, height: 24)
}

extension Report {
    var textBoxes: [TextBox] {
        get { textBoxesStorage ?? [] }
        set { textBoxesStorage = newValue.isEmpty ? nil : newValue }
    }
}
