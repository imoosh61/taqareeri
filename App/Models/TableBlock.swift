import Foundation

/// A simple table placed on a page: rows of cells, optional header row.
struct TableBlock: Codable, Equatable {
    /// rows × columns; every row has the same number of cells.
    var rows: [[String]] = [
        ["م", "البيان", "الملاحظات"],
        ["١", "", ""],
        ["٢", "", ""],
        ["٣", "", ""]
    ]
    var hasHeaderRow = true
    var fontSize: Double = 12
    var colorHex = "1F3A5F"

    static let maxRows = 30
    static let maxColumns = 8

    var rowCount: Int { rows.count }
    var columnCount: Int { rows.first?.count ?? 0 }

    mutating func addRow() {
        guard rowCount < Self.maxRows else { return }
        rows.append(Array(repeating: "", count: max(columnCount, 1)))
    }

    mutating func removeRow(at index: Int) {
        guard rowCount > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    mutating func addColumn() {
        guard columnCount < Self.maxColumns else { return }
        for index in rows.indices { rows[index].append("") }
    }

    mutating func removeColumn(at index: Int) {
        guard columnCount > 1, index >= 0, index < columnCount else { return }
        for row in rows.indices { rows[row].remove(at: index) }
    }

    /// Height that fits all rows at the current font size.
    var preferredHeight: CGFloat {
        CGFloat(rowCount) * CGFloat(fontSize) * 2.1
    }
}

/// Short line shown at the top of the first page (e.g. «عاجل», «سري»): centered, one line under the
/// letterhead and above the greeting.
struct TextMark: Codable, Equatable {
    var text = "عاجل"
    var colorHex = "C62828"
    var boxed = true
    var fontSize: Double = 15

    static let suggestions = ["عاجل", "عاجل جداً", "سري", "سري للغاية", "للاطلاع", "للأهمية", "تعميم"]

    var height: CGFloat {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : CGFloat(fontSize) * 2 + 8
    }
}
