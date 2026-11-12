import UIKit

/// Text of one page laid out with TextKit inside that page's writing area, flowing around its
/// elements. Text that does not fit is reported as overflow (never moved to another page silently).
@MainActor
final class PageTextLayout {
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let container: NSTextContainer
    /// Writing area in A4 points.
    let area: CGRect
    /// Character index where text stops fitting (nil = everything fits).
    let overflowLocation: Int?

    init(text: NSAttributedString, area: CGRect, exclusions: [CGRect]) {
        storage = NSTextStorage(attributedString: text)
        layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)
        container = NSTextContainer(size: area.size)
        container.lineFragmentPadding = 0
        container.exclusionPaths = DocumentLayout.localPaths(exclusions, in: area)
        layoutManager.addTextContainer(container)
        self.area = area

        let laidOut = layoutManager.glyphRange(for: container)
        let total = layoutManager.numberOfGlyphs
        if NSMaxRange(laidOut) < total {
            let location = layoutManager.characterIndexForGlyph(at: NSMaxRange(laidOut))
            let rest = (storage.string as NSString).substring(from: min(location, storage.length))
            // Extra empty lines at the end are not real overflow.
            overflowLocation = rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location
        } else {
            overflowLocation = nil
        }
    }

    func draw() {
        let range = layoutManager.glyphRange(for: container)
        guard range.length > 0 else { return }
        layoutManager.drawBackground(forGlyphRange: range, at: area.origin)
        layoutManager.drawGlyphs(forGlyphRange: range, at: area.origin)
    }
}

/// Everything needed to draw the document: the report, decoded images and each page's text layout.
@MainActor
final class DocumentSnapshot {
    let report: Report
    let spec: PageLayoutSpec
    let images: RenderImages
    let texts: [PageTextLayout]
    let signature: DocumentLayout.Placement?

    init(report: Report, images: RenderImages) {
        self.report = report
        self.images = images
        let spec = PageLayoutSpec(report: report)
        self.spec = spec
        let pages = report.pages
        let signature = DocumentLayout.signaturePlacement(report: report, spec: spec, pageCount: pages.count)
        self.signature = signature
        texts = pages.enumerated().map { index, page in
            PageTextLayout(
                text: BodyStyler.attributedString(from: page.body, settings: report.textStyle),
                area: DocumentLayout.textArea(report: report, spec: spec, page: index),
                exclusions: DocumentLayout.exclusions(report: report, spec: spec, page: index, signature: signature)
            )
        }
    }

    var pageCount: Int { texts.count }

    var overflowingPages: [Int] {
        texts.indices.filter { texts[$0].overflowLocation != nil }
    }

    func pageLabel(_ index: Int) -> String {
        ArabicFormat.pageLabel(index + 1, of: pageCount, report.page.numerals)
    }
}

/// Geometry rules of the page-based document.
@MainActor
enum DocumentLayout {
    struct Placement: Equatable {
        var page: Int
        var rect: CGRect
    }

    /// Space kept between body text and any element.
    static let elementMargin: CGFloat = 8

    /// Writing area of a page: the body area, below the fields on a form's first page.
    static func textArea(report: Report, spec: PageLayoutSpec, page: Int) -> CGRect {
        let body = spec.bodyRect(bodyPage: page)
        guard report.kind == .form && page == 0 else { return body }
        let top = min(max(body.minY, FormRenderer.layout(report: report, spec: spec).bottom + 14), body.maxY - 30)
        return CGRect(x: body.minX, y: top, width: body.width, height: body.maxY - top)
    }

    /// Areas the body text must avoid on a page (elements and signatures), in A4 points.
    static func exclusions(report: Report, spec: PageLayoutSpec, page: Int, signature: Placement?) -> [CGRect] {
        guard report.pages.indices.contains(page) else { return [] }
        var rects = report.pages[page].elements.map { $0.rect.insetBy(dx: -elementMargin, dy: -elementMargin) }
        if let signature, signature.page == page {
            rects.append(signature.rect.insetBy(dx: -elementMargin, dy: -elementMargin))
        }
        return rects
    }

    /// Converts page rects into exclusion paths local to a text area.
    static func localPaths(_ rects: [CGRect], in area: CGRect) -> [UIBezierPath] {
        rects.compactMap { rect in
            let local = rect.offsetBy(dx: -area.minX, dy: -area.minY)
                .intersection(CGRect(origin: .zero, size: area.size))
            return local.isNull || local.width <= 0 || local.height <= 0 ? nil : UIBezierPath(rect: local)
        }
    }

    // MARK: - Signatures

    static func signaturePlacement(report: Report, spec: PageLayoutSpec, pageCount: Int) -> Placement? {
        guard report.showsSignatures, pageCount > 0 else { return nil }
        let page = min(max(report.signaturePageValue ?? pageCount - 1, 0), pageCount - 1)
        let rect = report.signatureRectValue.map { clamp($0, minimum: CGSize(width: 120, height: 60)) }
            ?? defaultSignatureRect(spec: spec, page: page)
        return Placement(page: page, rect: rect)
    }

    static func defaultSignatureRect(spec: PageLayoutSpec, page: Int) -> CGRect {
        let body = spec.bodyRect(bodyPage: page)
        let height = max(spec.signatureBlockHeight, 60)
        return CGRect(x: body.minX, y: body.maxY - height, width: body.width, height: height)
    }

    // MARK: - New elements

    /// Default box for a new element: evidence fills the lower part of the writing area (above
    /// the signatures if they are on that page); a text box sits in the middle.
    static func defaultRect(for kind: PageElement.Kind, report: Report, spec: PageLayoutSpec, page: Int) -> CGRect {
        let area = textArea(report: report, spec: spec, page: page)
        switch kind {
        case .text:
            return CGRect(x: area.midX - 110, y: area.minY + min(area.height / 2, 200), width: 220, height: 60)
        case .evidence:
            var bottom = area.maxY
            if let signature = signaturePlacement(report: report, spec: spec, pageCount: report.pages.count),
               signature.page == page {
                bottom = min(bottom, signature.rect.minY - elementMargin * 2)
            }
            let isEmptyPage = report.pages.indices.contains(page) && report.pages[page].body.isEmpty
            let available = max(bottom - area.minY, 120)
            let height = isEmptyPage && report.kind == .text ? available * 0.6 : min(300, available * 0.55)
            return clamp(CGRect(x: area.minX, y: bottom - max(height, 120), width: area.width, height: max(height, 120)),
                         minimum: CGSize(width: 90, height: 70))
        }
    }

    /// Keeps a rect on the page with a minimum size.
    static func clamp(_ rect: CGRect, minimum: CGSize) -> CGRect {
        let page = CGRect(origin: .zero, size: A4.size).insetBy(dx: 6, dy: 6)
        var result = rect
        result.size.width = min(max(result.width, minimum.width), page.width)
        result.size.height = min(max(result.height, minimum.height), page.height)
        result.origin.x = min(max(result.minX, page.minX), page.maxX - result.width)
        result.origin.y = min(max(result.minY, page.minY), page.maxY - result.height)
        return result
    }
}
