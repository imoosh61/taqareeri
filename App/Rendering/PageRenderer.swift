import UIKit

/// Decoded images used while drawing (decoded once per change, not per page draw).
struct RenderImages {
    var logo: UIImage?
    var signature: UIImage?
    var stamp: UIImage?

    init() {}

    init(report: Report) {
        logo = report.header.logoPNG.flatMap { UIImage(data: $0) }
        signature = report.footer.signaturePNG.flatMap { UIImage(data: $0) }
        stamp = report.footer.stampPNG.flatMap { UIImage(data: $0) }
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
    static func draw(page: Int, context render: PageRenderContext, in ctx: CGContext) {
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
            FrameDrawer.draw(report.frame.style, color: accent, in: pageRect, context: ctx)
        }

        switch kind {
        case .cover:
            drawCover(report: report, images: render.images, page: pageRect, accent: accent)
        case .body(let bodyPage):
            drawBodyPage(bodyPage, render: render, accent: accent)
        }
    }

    // MARK: - Body pages

    private static func drawBodyPage(_ bodyPage: Int, render: PageRenderContext, accent: UIColor) {
        let report = render.report
        let pagination = render.pagination
        let spec = pagination.spec

        if spec.hasHeader(bodyPage: bodyPage) {
            drawHeader(report: report, logo: render.images.logo, in: spec.headerRect, accent: accent)
        }

        let bodyRect = spec.bodyRect(bodyPage: bodyPage)
        if let range = pagination.glyphRange(forBodyPage: bodyPage), range.length > 0 {
            pagination.layoutManager.drawBackground(forGlyphRange: range, at: bodyRect.origin)
            pagination.layoutManager.drawGlyphs(forGlyphRange: range, at: bodyRect.origin)
        }

        if report.footer.showSignatureBlock && bodyPage == pagination.lastBodyPage {
            let height = spec.signatureBlockHeight
            let blockRect = CGRect(x: bodyRect.minX, y: bodyRect.maxY - height, width: bodyRect.width, height: height)
            drawSignatureBlock(report: report, images: render.images, in: blockRect)
        }

        if report.page.showPageNumbers {
            let label = ArabicFormat.pageLabel(bodyPage + 1, of: pagination.bodyPageCount, report.page.numerals)
            TextDraw.draw(
                [label],
                in: spec.footerRect,
                font: BodyStyler.font(name: report.textStyle.fontName, size: 10, bold: false),
                color: UIColor(white: 0.35, alpha: 1),
                alignment: .center
            )
        }
    }

    // MARK: - Header

    static func drawHeader(report: Report, logo: UIImage?, in rect: CGRect, accent: UIColor) {
        let header = report.header
        let content = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 14)
        let logoSide = min(content.height, 104)
        let gap: CGFloat = 10
        let columnWidth = (content.width - logoSide - gap * 2) / 2

        let rightColumn = CGRect(x: content.maxX - columnWidth, y: content.minY, width: columnWidth, height: content.height)
        let leftColumn = CGRect(x: content.minX, y: content.minY, width: columnWidth, height: content.height)
        let fontName = report.textStyle.fontName

        TextDraw.draw(
            [header.topLine, header.ministry, header.generalAdministration, header.department],
            in: rightColumn,
            font: BodyStyler.font(name: fontName, size: 12.5, bold: true),
            color: .black,
            alignment: .center
        )

        TextDraw.draw(
            ArabicFormat.headerDateLines(header, numerals: report.page.numerals),
            in: leftColumn,
            font: BodyStyler.font(name: fontName, size: 11.5, bold: false),
            color: .black,
            alignment: .right
        )

        if let logo {
            let box = CGRect(x: content.midX - logoSide / 2, y: content.midY - logoSide / 2, width: logoSide, height: logoSide)
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

    // MARK: - Cover

    private static func drawCover(report: Report, images: RenderImages, page: CGRect, accent: UIColor) {
        let fontName = report.textStyle.fontName
        let sideInset: CGFloat = 72
        let width = page.width - sideInset * 2
        var y: CGFloat = 110

        if let logo = images.logo {
            let box = CGRect(x: page.midX - 85, y: y, width: 170, height: 170)
            logo.draw(in: Geometry.aspectFit(logo.size, in: box))
            y += 185
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

    private static func drawSignatureBlock(report: Report, images: RenderImages, in rect: CGRect) {
        let footer = report.footer
        let blockWidth: CGFloat = 210
        // Signature block sits on the left (end of an RTL line), stamp beside it.
        let block = CGRect(x: rect.minX, y: rect.minY, width: blockWidth, height: rect.height)

        let names = [footer.signerTitle, footer.signerName]
        TextDraw.draw(
            names,
            in: CGRect(x: block.minX, y: block.minY, width: blockWidth, height: 46),
            font: BodyStyler.font(name: report.textStyle.fontName, size: 13, bold: true),
            color: .black,
            alignment: .center,
            verticallyCentered: false
        )

        if let signature = images.signature {
            let box = CGRect(x: block.minX + 20, y: block.minY + 48, width: blockWidth - 40, height: rect.height - 52)
            signature.draw(in: Geometry.aspectFit(signature.size, in: box))
        }

        if let stamp = images.stamp {
            let side = min(rect.height, 112)
            let box = CGRect(x: block.maxX + 18, y: rect.midY - side / 2, width: side, height: side)
            stamp.draw(in: Geometry.aspectFit(stamp.size, in: box), blendMode: .multiply, alpha: 0.92)
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
        verticallyCentered: Bool = true
    ) {
        let text = lines.map(\.trimmed).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return }

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
}
