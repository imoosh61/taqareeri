import UIKit

/// Decoded images used while drawing (decoded once per change, not per page draw).
struct RenderImages {
    var logo: UIImage?
    var stamp: UIImage?
    var frame: UIImage?
    var letterheadTop: UIImage?
    var letterheadBottom: UIImage?
    var signatures: [UUID: UIImage] = [:]
    var evidencePhotos: [UUID: UIImage] = [:]
    var qrCodes: [UUID: QRMatrix] = [:]

    init() {}

    init(report: Report) {
        logo = report.header.logoPNG.flatMap { UIImage(data: $0) }
        stamp = report.footer.stampPNG.flatMap { UIImage(data: $0) }
        frame = report.frame.customFramePNG.flatMap { UIImage(data: $0) }
        letterheadTop = report.frame.letterheadTopPNG.flatMap { UIImage(data: $0) }
        letterheadBottom = report.frame.letterheadBottomPNG.flatMap { UIImage(data: $0) }
        for employee in report.footer.employees {
            if let data = employee.signaturePNG, let image = UIImage(data: data) {
                signatures[employee.id] = image
            }
        }
        for item in Self.evidenceItems(of: report) {
            switch item.kind {
            case .photo:
                if let data = item.imageData, let image = UIImage(data: data) {
                    evidencePhotos[item.id] = image
                }
            case .qr:
                if let matrix = QRMatrix.make(item.qrText) {
                    qrCodes[item.id] = matrix
                }
            }
        }
    }

    static func evidenceItems(of report: Report) -> [EvidenceItem] {
        report.pages.flatMap(\.elements).compactMap(\.evidence).flatMap(\.items)
    }

    /// The image-bearing parts of a report; when unchanged, decoded images can be reused.
    static func sources(of report: Report) -> [Data?] {
        [report.header.logoPNG, report.footer.stampPNG, report.frame.customFramePNG,
         report.frame.letterheadTopPNG, report.frame.letterheadBottomPNG]
            + report.footer.employees.map(\.signaturePNG)
            + evidenceItems(of: report).map { $0.kind == .photo ? $0.imageData : Data(($0.id.uuidString + $0.qrText).utf8) }
    }
}

/// Draws one page in A4 point space into the current Core Graphics context.
/// The same code renders the editor, previews, thumbnails and the vector PDF.
@MainActor
enum PageRenderer {
    /// - Parameter includeBody: false draws everything except the body text (the editor shows
    ///   live, editable text on top).
    static func draw(page index: Int, snapshot: DocumentSnapshot, in ctx: CGContext, includeBody: Bool = true) {
        let report = snapshot.report
        let spec = snapshot.spec
        let images = snapshot.images
        let pageRect = CGRect(origin: .zero, size: spec.pageSize)
        let accent = UIColor(hex: report.frame.colorHex)

        UIGraphicsPushContext(ctx)
        ctx.saveGState()
        defer {
            ctx.restoreGState()
            UIGraphicsPopContext()
        }

        UIColor.white.setFill()
        ctx.fill(pageRect)
        guard report.pages.indices.contains(index), snapshot.texts.indices.contains(index) else { return }

        FrameDrawer.draw(report.frame.style, color: accent, image: images.frame, in: pageRect, context: ctx)

        if let rect = spec.topLetterheadRect(bodyPage: index), let image = images.letterheadTop {
            image.draw(in: rect)
        }
        if let rect = spec.bottomLetterheadRect(bodyPage: index), let image = images.letterheadBottom {
            image.draw(in: rect)
        }

        if spec.hasHeader(bodyPage: index) {
            drawHeader(report: report, logo: images.logo, in: spec.headerRect(bodyPage: index), accent: accent)
        }
        if index == 0, spec.markHeight > 0, let mark = report.markStorage {
            drawMark(mark, fontName: report.textStyle.fontName, in: spec.markRect)
        }
        if index == 0 && spec.addresseeHeight > 0 {
            drawAddressee(report: report, in: spec.addresseeRect)
        }
        if report.kind == .form && index == 0 {
            FormRenderer.draw(report: report, spec: spec, accent: accent)
        }

        for element in report.pages[index].elements {
            switch element.kind {
            case .evidence:
                if let block = element.evidence, block.isVisible {
                    EvidenceLayout.draw(block, report: report, images: images, in: element.rect, accent: accent)
                }
            case .table:
                if let table = element.table {
                    TableRenderer.draw(table, fontName: report.textStyle.fontName, numerals: report.page.numerals, in: element.rect)
                }
            case .text:
                if let box = element.text {
                    drawTextBox(box, in: element.rect, fontName: report.textStyle.fontName)
                }
            }
        }

        if let signature = snapshot.signature, signature.page == index {
            drawSignatures(report: report, images: images, in: signature.rect)
        }

        if includeBody {
            snapshot.texts[index].draw()
        }

        if report.page.showPageNumbers {
            TextDraw.draw(
                [snapshot.pageLabel(index)],
                in: spec.footerRect(bodyPage: index),
                font: BodyStyler.font(name: report.textStyle.fontName, size: 10, bold: false),
                color: UIColor(white: 0.35, alpha: 1),
                alignment: .center
            )
        }
    }

    // MARK: - Letterhead

    static let defaultLogoSide: CGFloat = 104

    static func logoSide(_ header: HeaderInfo) -> CGFloat {
        defaultLogoSide * CGFloat(header.logoScale)
    }

    /// Square box the logo is fitted into: centered in the letterhead (large logos grow downward),
    /// then moved by the user's offset and kept on the page.
    static func logoBox(header: HeaderInfo, headerRect rect: CGRect) -> CGRect {
        let content = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 14)
        let side = logoSide(header)
        let top = side > content.height ? content.minY : content.midY - side / 2
        var box = CGRect(x: content.midX - side / 2, y: top, width: side, height: side)
            .offsetBy(dx: header.logoOffset.width, dy: header.logoOffset.height)
        let page = CGRect(origin: .zero, size: A4.size).insetBy(dx: 8, dy: 8)
        box.origin.x = min(max(box.minX, page.minX), page.maxX - box.width)
        box.origin.y = min(max(box.minY, page.minY), page.maxY - box.height)
        return box
    }

    static func drawHeader(report: Report, logo: UIImage?, in rect: CGRect, accent: UIColor) {
        let header = report.header
        let content = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 14)
        let logoSide = Self.logoSide(header)
        let gap: CGFloat = 10
        let columnWidth = (content.width - logoSide - gap * 2) / 2

        let page = CGRect(origin: .zero, size: A4.size).insetBy(dx: 10, dy: 0)
        func shifted(_ column: CGRect, by offset: Double) -> CGRect {
            var moved = column.offsetBy(dx: CGFloat(offset), dy: 0)
            moved.origin.x = min(max(moved.minX, page.minX), page.maxX - moved.width)
            return moved
        }
        let rightColumn = shifted(
            CGRect(x: content.maxX - columnWidth, y: content.minY, width: columnWidth, height: content.height),
            by: header.adminOffset
        )
        let leftColumn = shifted(
            CGRect(x: content.minX, y: content.minY, width: columnWidth, height: content.height),
            by: header.dateOffset
        )
        let fontName = report.textStyle.fontName

        TextDraw.draw(
            [header.topLine, header.ministry, header.generalAdministration, header.department],
            in: rightColumn,
            font: BodyStyler.font(name: fontName, size: CGFloat(header.adminFontSize), bold: true),
            color: .black,
            alignment: header.adminAlignment.nsAlignment,
            shrinkToFit: true
        )

        TextDraw.draw(
            ArabicFormat.headerDateLines(header, numerals: report.page.numerals),
            in: leftColumn,
            font: BodyStyler.font(name: fontName, size: CGFloat(header.dateFontSize), bold: false),
            color: .black,
            alignment: header.dateAlignment.nsAlignment,
            shrinkToFit: true
        )

        if let logo {
            let box = logoBox(header: header, headerRect: rect)
            logo.draw(in: Geometry.aspectFit(logo.size, in: box))
        }

        let lineY = rect.maxY - 7
        accent.setStroke()
        let thick = UIBezierPath()
        thick.move(to: CGPoint(x: rect.minX, y: lineY))
        thick.addLine(to: CGPoint(x: rect.maxX, y: lineY))
        thick.lineWidth = 1.6
        thick.stroke()
        let thin = UIBezierPath()
        thin.move(to: CGPoint(x: rect.minX, y: lineY + 3.5))
        thin.addLine(to: CGPoint(x: rect.maxX, y: lineY + 3.5))
        thin.lineWidth = 0.6
        thin.stroke()
    }

    // MARK: - Text boxes

    static func drawTextBox(_ box: TextBox, in rect: CGRect, fontName: String) {
        if box.showBorder {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            UIColor(white: 0.45, alpha: 1).setStroke()
            path.lineWidth = 0.9
            path.stroke()
        }
        let inner = box.showBorder ? rect.insetBy(dx: 8, dy: 5) : rect.insetBy(dx: 2, dy: 1)
        TextDraw.draw(
            box.text.components(separatedBy: "\n"),
            in: inner,
            font: BodyStyler.font(name: fontName, size: CGFloat(box.fontSize), bold: box.bold),
            color: UIColor(hex: box.colorHex),
            alignment: box.alignment.nsAlignment,
            verticallyCentered: true,
            shrinkToFit: true
        )
    }

    // MARK: - Mark («عاجل»)

    static func drawMark(_ mark: TextMark, fontName: String, in rect: CGRect) {
        let text = mark.text.trimmed
        guard !text.isEmpty else { return }
        let color = UIColor(hex: mark.colorHex)
        let font = BodyStyler.font(name: fontName, size: CGFloat(mark.fontSize), bold: true)
        let width = min((text as NSString).size(withAttributes: [.font: font]).width + CGFloat(mark.fontSize) * 2, rect.width)
        let box = CGRect(x: rect.midX - width / 2, y: rect.minY + 2, width: width, height: rect.height - 6)
        if mark.boxed {
            let path = UIBezierPath(roundedRect: box, cornerRadius: 4)
            color.setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }
        TextDraw.draw([text], in: box, font: font, color: color, alignment: .center, verticallyCentered: true, shrinkToFit: true)
    }

    // MARK: - Addressee

    /// Recipient title (right), then name on the right with the honorific at the far left of the
    /// same line, then the optional greeting centered.
    private static func drawAddressee(report: Report, in rect: CGRect) {
        let addressee = report.addressee
        let fontName = report.textStyle.fontName
        let size = CGFloat(report.addresseeFontSize)
        let lineHeight = PageLayoutSpec.addresseeLineHeight(fontSize: report.addresseeFontSize)
        let bold = BodyStyler.font(name: fontName, size: size, bold: true)
        let regular = BodyStyler.font(name: fontName, size: size, bold: false)
        var y = rect.minY

        func line() -> CGRect { CGRect(x: rect.minX, y: y, width: rect.width, height: lineHeight) }

        if !addressee.recipientTitle.trimmed.isEmpty {
            TextDraw.draw([addressee.recipientTitle], in: line(), font: bold, color: .black, alignment: .right)
            y += lineHeight
        }

        let showHonorific = addressee.showHonorific && !addressee.honorific.trimmed.isEmpty
        if !addressee.recipientName.trimmed.isEmpty || showHonorific {
            let row = line()
            if showHonorific {
                let honorificWidth = min(rect.width * 0.35, 160)
                TextDraw.draw(
                    [addressee.honorific],
                    in: CGRect(x: row.minX, y: row.minY, width: honorificWidth, height: row.height),
                    font: bold, color: .black, alignment: .left
                )
                TextDraw.draw(
                    [addressee.recipientName],
                    in: CGRect(x: row.minX + honorificWidth + 12, y: row.minY, width: row.width - honorificWidth - 12, height: row.height),
                    font: bold, color: .black, alignment: .right
                )
            } else {
                TextDraw.draw([addressee.recipientName], in: row, font: bold, color: .black, alignment: .right)
            }
            y += lineHeight
        }

        if addressee.showGreeting && !addressee.greeting.trimmed.isEmpty {
            TextDraw.draw([addressee.greeting], in: line(), font: regular, color: .black, alignment: .center)
        }
    }

    // MARK: - Signatures

    /// Names & signatures inside their block: one employee centered; several two per row
    /// (first on the right), an odd last one centered; the stamp between the columns.
    static func drawSignatures(report: Report, images: RenderImages, in rect: CGRect) {
        let employees = report.footer.employees
        let rows = employees.isEmpty ? 0 : (employees.count + 1) / 2
        let rowHeight = rows > 0 ? rect.height / CGFloat(rows) : rect.height
        let cellWidth = min(220, rect.width * 0.42)
        let fontName = report.textStyle.fontName
        var firstCell: CGRect?

        for (index, employee) in employees.enumerated() {
            let y = rect.minY + CGFloat(index / 2) * rowHeight
            let alone = employees.count == 1 || (index == employees.count - 1 && index.isMultiple(of: 2))
            let x: CGFloat
            if alone {
                x = rect.midX - cellWidth / 2
            } else if index.isMultiple(of: 2) {
                x = rect.maxX - cellWidth
            } else {
                x = rect.minX
            }
            let cell = CGRect(x: x, y: y, width: cellWidth, height: rowHeight)
            if index == 0 { firstCell = cell }
            drawEmployee(employee, signature: images.signatures[employee.id], in: cell, fontName: fontName)
        }

        guard let stamp = images.stamp else { return }
        let side = min(100, rect.height)
        let center: CGPoint
        if employees.count >= 2 {
            center = CGPoint(x: rect.midX, y: rect.minY + min(rowHeight, rect.height) / 2)
        } else if let cell = firstCell {
            center = CGPoint(x: max(rect.minX + side / 2, cell.minX - side / 2 - 10), y: cell.midY)
        } else {
            center = CGPoint(x: rect.midX, y: rect.midY)
        }
        let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        stamp.draw(in: Geometry.aspectFit(stamp.size, in: box), blendMode: .multiply, alpha: 0.92)
    }

    private static func drawEmployee(_ employee: Employee, signature: UIImage?, in cell: CGRect, fontName: String) {
        TextDraw.draw(
            [employee.label],
            in: CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: 22),
            font: BodyStyler.font(name: fontName, size: 13, bold: true),
            color: .black,
            alignment: .center,
            verticallyCentered: false
        )
        TextDraw.draw(
            [employee.name],
            in: CGRect(x: cell.minX, y: cell.minY + 24, width: cell.width, height: 22),
            font: BodyStyler.font(name: fontName, size: 13, bold: false),
            color: .black,
            alignment: .center,
            verticallyCentered: false
        )
        if let signature {
            let box = CGRect(x: cell.minX + 24, y: cell.minY + 50, width: cell.width - 48, height: cell.height - 54)
            signature.draw(in: Geometry.aspectFit(signature.size, in: box))
        }
    }
}

/// Multi-line RTL text drawing helper.
@MainActor
enum TextDraw {
    static func draw(
        _ lines: [String],
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        lineSpacing: CGFloat = 3,
        verticallyCentered: Bool = true,
        shrinkToFit: Bool = false
    ) {
        let text = lines.map(\.trimmed).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return }

        // Reduce the size step by step until every line fits, so text never gets cut off.
        var font = font
        if shrinkToFit {
            while font.pointSize > 6.5,
                  measuredHeight(text, font: font, width: rect.width, lineSpacing: lineSpacing) > rect.height {
                font = font.withSize(font.pointSize - 0.5)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping

        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let measured = attributed.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: options,
            context: nil
        )

        var target = rect
        let height = ceil(measured.height)
        if verticallyCentered && height < rect.height {
            target.origin.y += (rect.height - height) / 2
            target.size.height = height + 1
        }
        attributed.draw(with: target, options: options.union(.truncatesLastVisibleLine), context: nil)
    }

    private static func measuredHeight(_ text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }
}
