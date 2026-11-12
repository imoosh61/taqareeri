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
        for item in report.evidenceBlocks.flatMap(\.items) {
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

    /// The image-bearing parts of a report; when unchanged, decoded images can be reused.
    static func sources(of report: Report) -> [Data?] {
        [report.header.logoPNG, report.footer.stampPNG, report.frame.customFramePNG,
         report.frame.letterheadTopPNG, report.frame.letterheadBottomPNG]
            + report.footer.employees.map(\.signaturePNG)
            + report.evidenceBlocks.flatMap(\.items).map { $0.kind == .photo ? $0.imageData : Data(($0.id.uuidString + $0.qrText).utf8) }
    }
}

struct PageRenderContext {
    let report: Report
    let pagination: PaginationResult
    let images: RenderImages
}

/// Draws one physical page in A4 point space into the current UIKit/Core Graphics context.
/// The same code path renders on-screen previews and the vector PDF.
@MainActor
enum PageRenderer {
    /// - Parameter includeBody: false draws only the page furniture (frame, letterhead, addressee,
    ///   signatures, page number) — used behind the live on-page editor.
    static func draw(page: Int, context render: PageRenderContext, in ctx: CGContext, includeBody: Bool = true) {
        let report = render.report
        let pagination = render.pagination
        let pageRect = CGRect(origin: .zero, size: pagination.spec.pageSize)
        let accent = UIColor(hex: report.frame.colorHex)

        UIGraphicsPushContext(ctx)
        ctx.saveGState()
        defer {
            ctx.restoreGState()
            UIGraphicsPopContext()
        }

        UIColor.white.setFill()
        ctx.fill(pageRect)

        let kind = pagination.kind(ofPage: page)
        let isCover = kind == .cover
        if !isCover || report.frame.applyToCover {
            FrameDrawer.draw(report.frame.style, color: accent, image: render.images.frame, in: pageRect, context: ctx)
        }

        switch kind {
        case .cover:
            drawCover(report: report, images: render.images, page: pageRect, accent: accent)
        case .body(let bodyPage):
            drawBodyPage(bodyPage, render: render, accent: accent, includeBody: includeBody)
        }
    }

    // MARK: - Body pages

    private static func drawBodyPage(_ bodyPage: Int, render: PageRenderContext, accent: UIColor, includeBody: Bool) {
        let report = render.report
        let pagination = render.pagination
        let spec = pagination.spec

        // Organisation letterhead images (top banner, bottom contact bar).
        if let rect = spec.topLetterheadRect(bodyPage: bodyPage), let image = render.images.letterheadTop {
            image.draw(in: rect)
        }
        if let rect = spec.bottomLetterheadRect(bodyPage: bodyPage), let image = render.images.letterheadBottom {
            image.draw(in: rect)
        }

        if spec.hasHeader(bodyPage: bodyPage) {
            drawHeader(report: report, logo: render.images.logo, in: spec.headerRect(bodyPage: bodyPage), accent: accent)
        }

        if bodyPage == 0 && spec.addresseeHeight > 0 {
            drawAddressee(report: report, in: spec.addresseeRect)
        }

        if report.kind == .form && bodyPage == 0 {
            FormRenderer.draw(report: report, spec: spec, accent: accent)
        }

        for block in report.visibleEvidenceBlocks {
            let placement = EvidenceLayout.placement(of: block, report: report, spec: spec)
            if placement.page == bodyPage {
                EvidenceLayout.draw(block, report: report, images: render.images, in: placement.rect, accent: accent)
            }
        }

        for box in report.textBoxes where min(box.page, pagination.lastBodyPage) == bodyPage {
            drawTextBox(box, fontName: report.textStyle.fontName)
        }

        let bodyRect = spec.bodyRect(bodyPage: bodyPage)
        if includeBody, let range = pagination.glyphRange(forBodyPage: bodyPage), range.length > 0 {
            pagination.layoutManager.drawBackground(forGlyphRange: range, at: bodyRect.origin)
            pagination.layoutManager.drawGlyphs(forGlyphRange: range, at: bodyRect.origin)
        }

        if report.footer.showSignatureBlock && bodyPage == pagination.lastBodyPage {
            drawSignatureBlock(report: report, images: render.images, layout: signatureLayout(report: report, spec: spec, lastBodyPage: bodyPage, hasStamp: render.images.stamp != nil))
        }

        if report.page.showPageNumbers {
            let label = ArabicFormat.pageLabel(bodyPage + 1, of: pagination.bodyPageCount, report.page.numerals)
            TextDraw.draw(
                [label],
                in: spec.footerRect(bodyPage: bodyPage),
                font: BodyStyler.font(name: report.textStyle.fontName, size: 10, bold: false),
                color: UIColor(white: 0.35, alpha: 1),
                alignment: .center
            )
        }
    }

    // MARK: - Header

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

    private static func drawTextBox(_ box: TextBox, fontName: String) {
        if box.showBorder {
            let path = UIBezierPath(roundedRect: box.rect, cornerRadius: 6)
            UIColor(white: 0.45, alpha: 1).setStroke()
            path.lineWidth = 0.9
            path.stroke()
        }
        let inner = box.showBorder ? box.rect.insetBy(dx: 8, dy: 5) : box.rect.insetBy(dx: 2, dy: 1)
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

    // MARK: - Cover

    private static func drawCover(report: Report, images: RenderImages, page: CGRect, accent: UIColor) {
        let fontName = report.textStyle.fontName
        let sideInset: CGFloat = 72
        let width = page.width - sideInset * 2
        var y: CGFloat = 110

        if let logo = images.logo {
            let side = 170 * CGFloat(min(report.header.logoScale, 1.3))
            let box = CGRect(x: page.midX - side / 2, y: y, width: side, height: side)
            logo.draw(in: Geometry.aspectFit(logo.size, in: box))
            y += side + 15
        } else {
            y += 60
        }

        let header = report.header
        TextDraw.draw(
            [header.topLine, header.ministry, header.generalAdministration, header.department],
            in: CGRect(x: sideInset, y: y, width: width, height: 120),
            font: BodyStyler.font(name: fontName, size: 15, bold: true),
            color: .black,
            alignment: .center,
            verticallyCentered: false
        )

        let titleRect = CGRect(x: sideInset, y: page.height * 0.47, width: width, height: 130)
        TextDraw.draw(
            [report.title],
            in: titleRect,
            font: BodyStyler.font(name: fontName, size: 30, bold: true),
            color: accent,
            alignment: .center
        )

        // Ornament under the title
        let ornamentY = titleRect.maxY + 10
        accent.setStroke()
        accent.setFill()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: page.midX - 110, y: ornamentY))
        line.addLine(to: CGPoint(x: page.midX - 14, y: ornamentY))
        line.move(to: CGPoint(x: page.midX + 14, y: ornamentY))
        line.addLine(to: CGPoint(x: page.midX + 110, y: ornamentY))
        line.lineWidth = 1
        line.stroke()
        if let ctx = UIGraphicsGetCurrentContext() {
            ctx.addPath(FrameDrawer.star(center: CGPoint(x: page.midX, y: ornamentY), radius: 7))
            ctx.fillPath()
        }

        if !report.cover.subtitle.trimmed.isEmpty {
            TextDraw.draw(
                [report.cover.subtitle],
                in: CGRect(x: sideInset, y: ornamentY + 18, width: width, height: 80),
                font: BodyStyler.font(name: fontName, size: 18, bold: false),
                color: UIColor(white: 0.25, alpha: 1),
                alignment: .center,
                verticallyCentered: false
            )
        }

        var bottomLines: [String] = []
        if !report.cover.preparedBy.trimmed.isEmpty {
            bottomLines.append("إعداد: " + report.cover.preparedBy.trimmed)
        }
        bottomLines.append(contentsOf: ArabicFormat.coverDateLines(header, numerals: report.page.numerals))
        TextDraw.draw(
            bottomLines,
            in: CGRect(x: sideInset, y: page.height - 200, width: width, height: 100),
            font: BodyStyler.font(name: fontName, size: 13, bold: false),
            color: .black,
            alignment: .center
        )
    }

    // MARK: - Signature & stamp

    /// Final rectangles (in A4 points) of each employee cell and the stamp on the last page.
    struct SignatureLayout {
        var employees: [(id: UUID, rect: CGRect)]
        var stamp: CGRect?
    }

    static let stampSide: CGFloat = 100

    /// Automatic placement — one employee centered; several two per row, first on the right (RTL),
    /// then left; an odd last one centered on its own row; stamp between the columns — then each
    /// element is shifted by its user offset and kept inside the page.
    static func signatureLayout(report: Report, spec: PageLayoutSpec, lastBodyPage: Int, hasStamp: Bool) -> SignatureLayout {
        let bodyRect = spec.bodyRect(bodyPage: lastBodyPage)
        let height = spec.signatureBlockHeight
        let rect = CGRect(x: bodyRect.minX, y: bodyRect.maxY - height, width: bodyRect.width, height: height)
        let page = CGRect(origin: .zero, size: spec.pageSize)

        let employees = report.footer.employees
        let rowHeight = PageLayoutSpec.employeeRowHeight
        let cellWidth = min(220, rect.width * 0.42)
        var cells: [(id: UUID, rect: CGRect)] = []
        var firstCell: CGRect?

        for (index, employee) in employees.enumerated() {
            let y = rect.minY + CGFloat(index / 2) * rowHeight
            let isAloneInRow = employees.count == 1 || (index == employees.count - 1 && index.isMultiple(of: 2))
            let x: CGFloat
            if isAloneInRow {
                x = rect.midX - cellWidth / 2
            } else if index.isMultiple(of: 2) {
                x = rect.maxX - cellWidth   // right
            } else {
                x = rect.minX               // left
            }
            let cell = CGRect(x: x, y: y, width: cellWidth, height: rowHeight)
            if index == 0 { firstCell = cell }
            cells.append((employee.id, clamp(cell.offsetBy(dx: employee.offset.width, dy: employee.offset.height), to: page)))
        }

        var stampRect: CGRect?
        if hasStamp {
            let side = stampSide
            let center: CGPoint
            if employees.count >= 2 {
                center = CGPoint(x: rect.midX, y: rect.minY + rowHeight / 2 + 4)
            } else if let cell = firstCell {
                center = CGPoint(x: max(rect.minX + side / 2, cell.minX - side / 2 - 10), y: cell.midY)
            } else {
                center = CGPoint(x: rect.midX, y: rect.minY + side / 2 + 4)
            }
            let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            let offset = report.footer.stampOffset
            stampRect = clamp(box.offsetBy(dx: offset.width, dy: offset.height), to: page)
        }
        return SignatureLayout(employees: cells, stamp: stampRect)
    }

    /// Keeps `rect` fully inside `bounds` (with a small inset).
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let inner = bounds.insetBy(dx: 8, dy: 8)
        var result = rect
        result.origin.x = min(max(result.minX, inner.minX), inner.maxX - result.width)
        result.origin.y = min(max(result.minY, inner.minY), inner.maxY - result.height)
        return result
    }

    private static func drawSignatureBlock(report: Report, images: RenderImages, layout: SignatureLayout) {
        let fontName = report.textStyle.fontName
        for (employee, cell) in zip(report.footer.employees, layout.employees) where employee.id == cell.id {
            drawEmployee(employee, signature: images.signatures[employee.id], in: cell.rect, fontName: fontName)
        }
        if let stamp = images.stamp, let box = layout.stamp {
            stamp.draw(in: Geometry.aspectFit(stamp.size, in: box), blendMode: .multiply, alpha: 0.92)
        }
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
