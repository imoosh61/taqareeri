import UIKit

/// Draws a table element (right-to-left: the first column is on the right).
@MainActor
enum TableRenderer {
    static func draw(_ table: TableBlock, fontName: String, numerals: NumeralStyle, in rect: CGRect) {
        let rows = table.rowCount
        let columns = table.columnCount
        guard rows > 0, columns > 0, rect.width > 10, rect.height > 10 else { return }

        let accent = UIColor(hex: table.colorHex)
        let rowHeight = rect.height / CGFloat(rows)
        let columnWidth = rect.width / CGFloat(columns)
        let fontSize = min(CGFloat(table.fontSize), rowHeight * 0.6)
        let regular = BodyStyler.font(name: fontName, size: fontSize, bold: false)
        let bold = BodyStyler.font(name: fontName, size: fontSize, bold: true)

        func cell(_ row: Int, _ column: Int) -> CGRect {
            // Column 0 starts at the right edge.
            CGRect(x: rect.maxX - CGFloat(column + 1) * columnWidth, y: rect.minY + CGFloat(row) * rowHeight,
                   width: columnWidth, height: rowHeight)
        }

        if table.hasHeaderRow {
            accent.setFill()
            UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowHeight))
        }
        // Light banding for readability.
        for row in stride(from: table.hasHeaderRow ? 2 : 1, to: rows, by: 2) {
            accent.withAlphaComponent(0.06).setFill()
            UIRectFill(CGRect(x: rect.minX, y: rect.minY + CGFloat(row) * rowHeight, width: rect.width, height: rowHeight))
        }

        for row in 0..<rows {
            let isHeader = table.hasHeaderRow && row == 0
            for column in 0..<columns {
                let text = table.rows[row][column]
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                TextDraw.draw(
                    [text],
                    in: cell(row, column).insetBy(dx: 4, dy: 2),
                    font: isHeader ? bold : regular,
                    color: isHeader ? .white : .black,
                    alignment: .center,
                    verticallyCentered: true,
                    shrinkToFit: true
                )
            }
        }

        // Grid lines.
        let grid = UIBezierPath()
        for row in 1..<rows {
            let y = rect.minY + CGFloat(row) * rowHeight
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        for column in 1..<columns {
            let x = rect.minX + CGFloat(column) * columnWidth
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        UIColor(white: 0.55, alpha: 1).setStroke()
        grid.lineWidth = 0.6
        grid.stroke()

        let border = UIBezierPath(rect: rect)
        accent.setStroke()
        border.lineWidth = 1.2
        border.stroke()
    }
}
