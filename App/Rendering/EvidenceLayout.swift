import UIKit

/// How an evidence box arranges its photos / QR codes and title.
@MainActor
enum EvidenceLayout {
    // MARK: - Drawing

    static func draw(_ evidence: EvidenceBlock, report: Report, images: RenderImages, in rect: CGRect, accent: UIColor) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let fontName = report.textStyle.fontName
        let title = evidence.title.trimmed
        let titleFont = BodyStyler.font(name: fontName, size: 13, bold: true)

        if evidence.showBorder {
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 10)
            UIColor(white: 0.62, alpha: 1).setStroke()
            border.lineWidth = 0.9
            border.stroke()
        }

        var inner = rect.insetBy(dx: 10, dy: 10)
        if !title.isEmpty {
            let size = (title as NSString).size(withAttributes: [.font: titleFont])
            let width = min(size.width + 20, rect.width - 20)
            if evidence.showBorder {
                // Title centered on the top border.
                let titleRect = CGRect(x: rect.midX - width / 2, y: rect.minY - size.height / 2 - 1, width: width, height: size.height + 2)
                ctx.saveGState()
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(titleRect)
                ctx.restoreGState()
                TextDraw.draw([title], in: titleRect, font: titleFont, color: accent, alignment: .center, shrinkToFit: true)
                inner = CGRect(x: inner.minX, y: inner.minY + 6, width: inner.width, height: inner.height - 6)
            } else {
                let titleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: size.height + 4)
                TextDraw.draw([title], in: titleRect, font: titleFont, color: accent, alignment: .center, shrinkToFit: true)
                inner = CGRect(x: rect.minX, y: titleRect.maxY + 4, width: rect.width, height: rect.height - titleRect.height - 4)
            }
        }

        let items = Array(evidence.items.prefix(EvidenceBlock.maxItems))
        let cells = gridCells(count: items.count, in: inner, gap: 8)
        let captionFont = BodyStyler.font(name: fontName, size: 10.5, bold: false)

        for (item, cell) in zip(items, cells) {
            let caption = item.caption.trimmed
            let captionHeight: CGFloat = caption.isEmpty ? 0 : 17
            let content = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: max(cell.height - captionHeight, 10))

            switch item.kind {
            case .photo:
                if let image = images.evidencePhotos[item.id] {
                    ctx.saveGState()
                    UIBezierPath(roundedRect: content, cornerRadius: 6).addClip()
                    let target = evidence.fillCells
                        ? Geometry.aspectFill(image.size, in: content)
                        : Geometry.aspectFit(image.size, in: content)
                    image.draw(in: target)
                    ctx.restoreGState()
                }
            case .qr:
                images.qrCodes[item.id]?.draw(in: content.insetBy(dx: 2, dy: 2), context: ctx)
            }

            if !caption.isEmpty {
                TextDraw.draw(
                    [caption],
                    in: CGRect(x: cell.minX, y: content.maxY + 2, width: cell.width, height: captionHeight - 2),
                    font: captionFont,
                    color: UIColor(white: 0.2, alpha: 1),
                    alignment: .center,
                    shrinkToFit: true
                )
            }
        }
    }

    /// Cells for 1–4 items, first item on the right (RTL). Wide blocks use one row.
    static func gridCells(count: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
        let ratio = rect.width / rect.height

        func row(_ n: Int, y: CGFloat, height: CGFloat, width: CGFloat? = nil) -> [CGRect] {
            let cellWidth = width ?? (rect.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let total = cellWidth * CGFloat(n) + gap * CGFloat(n - 1)
            var x = rect.midX + total / 2
            return (0..<n).map { _ in
                defer { x -= cellWidth + gap }
                return CGRect(x: x - cellWidth, y: y, width: cellWidth, height: height)
            }
        }

        let halfHeight = (rect.height - gap) / 2
        switch count {
        case 1:
            return [rect]
        case 2:
            if ratio >= 1 { return row(2, y: rect.minY, height: rect.height) }
            return [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: halfHeight),
                    CGRect(x: rect.minX, y: rect.minY + halfHeight + gap, width: rect.width, height: halfHeight)]
        case 3:
            if ratio >= 2.2 { return row(3, y: rect.minY, height: rect.height) }
            let width = (rect.width - gap) / 2
            return row(2, y: rect.minY, height: halfHeight) + row(1, y: rect.minY + halfHeight + gap, height: halfHeight, width: width)
        default:
            if ratio >= 3 { return row(4, y: rect.minY, height: rect.height) }
            return row(2, y: rect.minY, height: halfHeight) + row(2, y: rect.minY + halfHeight + gap, height: halfHeight)
        }
    }
}
