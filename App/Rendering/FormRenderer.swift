import UIKit

/// Lays out and draws form reports: title bar + labelled boxes, filled right-to-left in rows.
@MainActor
enum FormRenderer {
    struct Layout {
        var titleRect: CGRect?
        var boxes: [(field: FormField, rect: CGRect)]
        /// Bottom of the last box (where the evidence block starts by default).
        var bottom: CGFloat
    }

    static let titleBarHeight: CGFloat = 32
    static let columnGap: CGFloat = 10
    static let rowGap: CGFloat = 16
    static let labelInset: CGFloat = 8

    static func lineHeight(_ report: Report) -> CGFloat {
        CGFloat(report.form.valueFontSize) * 1.65
    }

    static func layout(report: Report, spec: PageLayoutSpec) -> Layout {
        let area = spec.bodyRect(bodyPage: 0)
        var y = area.minY
        var titleRect: CGRect?

        if report.form.showTitleBar {
            titleRect = CGRect(x: area.minX, y: y, width: area.width, height: titleBarHeight)
            y += titleBarHeight + 18
        }

        // Group fields into rows whose widths add up to at most one full line.
        var rows: [[FormField]] = []
        var current: [FormField] = []
        var used = 0.0
        for field in report.form.fields {
            if !current.isEmpty && used + field.width.fraction > 1.0001 {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(field)
            used += field.width.fraction
        }
        if !current.isEmpty { rows.append(current) }

        let lineHeight = lineHeight(report)
        var boxes: [(FormField, CGRect)] = []
        for row in rows {
            let total = row.reduce(0) { $0 + $1.width.fraction }
            let available = area.width - columnGap * CGFloat(row.count - 1)
            let height = CGFloat(row.map(\.lines).max() ?? 1) * lineHeight + 18
            var x = area.maxX   // right to left
            for field in row {
                let width = available * CGFloat(field.width.fraction / total)
                boxes.append((field, CGRect(x: x - width, y: y + labelInset, width: width, height: height)))
                x -= width + columnGap
            }
            y += labelInset + height + rowGap
        }
        return Layout(titleRect: titleRect, boxes: boxes, bottom: y - rowGap)
    }

    static func draw(report: Report, spec: PageLayoutSpec, accent: UIColor) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let layout = layout(report: report, spec: spec)
        let fontName = report.textStyle.fontName

        if let title = layout.titleRect {
            let path = UIBezierPath(roundedRect: title, cornerRadius: 10)
            accent.setFill()
            path.fill()
            TextDraw.draw(
                [report.title],
                in: title.insetBy(dx: 14, dy: 2),
                font: BodyStyler.font(name: fontName, size: 15, bold: true),
                color: .white,
                alignment: .center,
                shrinkToFit: true
            )
        }

        let labelFont = BodyStyler.font(name: fontName, size: 11.5, bold: true)
        let valueFont = BodyStyler.font(name: fontName, size: CGFloat(report.form.valueFontSize), bold: false)
        let border = UIColor(white: 0.62, alpha: 1)

        for (field, rect) in layout.boxes {
            let box = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            border.setStroke()
            box.lineWidth = 0.9
            box.stroke()

            // Label sits on the top border at the right, cutting the line (as in printed forms).
            let label = field.label.trimmed
            if !label.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
                let size = (label as NSString).size(withAttributes: attributes)
                let width = min(size.width + 12, rect.width - 20)
                let labelRect = CGRect(x: rect.maxX - 12 - width, y: rect.minY - size.height / 2 - 1, width: width, height: size.height + 2)
                ctx.saveGState()
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(labelRect)
                ctx.restoreGState()
                TextDraw.draw([label + ":"], in: labelRect, font: labelFont, color: accent, alignment: .center, shrinkToFit: true)
            }

            let inner = rect.insetBy(dx: 10, dy: 8).offsetBy(dx: 0, dy: 2)
            TextDraw.draw(
                [field.value],
                in: inner,
                font: valueFont,
                color: .black,
                alignment: field.lines == 1 ? .center : .justified,
                verticallyCentered: true,
                shrinkToFit: true
            )
        }
    }
}
