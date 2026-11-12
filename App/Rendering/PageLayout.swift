import UIKit

enum A4 {
    /// ISO 216 A4 in PostScript points (1/72 inch).
    static let size = CGSize(width: 595.28, height: 841.89)
    static let bounds = CGRect(origin: .zero, size: size)
    static let aspectRatio = size.width / size.height
}

/// Geometry of every page: margins, header area, body text area and footer.
struct PageLayoutSpec {
    let pageSize = A4.size
    let marginHorizontal: CGFloat
    let marginTop: CGFloat
    let marginBottom: CGFloat
    /// Where the letterhead starts. Like Word's header area, it may sit inside the top margin.
    let headerTop: CGFloat
    let headerHeight: CGFloat = 132
    let headerGap: CGFloat = 12
    let headerEnabled: Bool
    let headerOnAllPages: Bool
    let reservesFooter: Bool
    /// Height reserved on the last page for signature & stamp (0 when disabled).
    let signatureBlockHeight: CGFloat
    /// Height of the optional addressee block at the top of the first text page.
    let addresseeHeight: CGFloat
    /// Height of the optional mark line («عاجل») at the top of the first page.
    let markHeight: CGFloat
    /// Organisation letterhead images (zero size when absent).
    let topLetterheadSize: CGSize
    let bottomLetterheadSize: CGSize
    let letterheadOnAllPages: Bool
    let topLetterheadOffset: CGFloat
    let bottomLetterheadOffset: CGFloat
    static let letterheadGap: CGFloat = 10

    init(report: Report) {
        let margins = report.page.margins
        marginHorizontal = margins.horizontal
        marginTop = margins.top
        marginBottom = margins.bottom
        if margins == .compact {
            headerTop = margins.top
        } else {
            // Stay inside decorative frames (drawn up to ~40 pt from the edge).
            headerTop = min(margins.top, report.frame.style == .none ? 34 : 46)
        }
        headerEnabled = report.header.isEnabled
        headerOnAllPages = report.header.placement == .allPages
        reservesFooter = report.page.showPageNumbers
        signatureBlockHeight = report.footer.showSignatureBlock ? Self.signatureHeight(for: report.footer) : 0
        addresseeHeight = Self.addresseeHeight(for: report)
        markHeight = report.markStorage?.height ?? 0

        let frame = report.frame
        func size(_ data: Data?, _ aspect: Double?, _ scale: Double) -> CGSize {
            guard data != nil, let aspect, aspect > 0 else { return .zero }
            let width = A4.size.width * CGFloat(min(max(scale, 0.1), 1))
            return CGSize(width: width, height: min(width * CGFloat(aspect), A4.size.height * 0.3))
        }
        topLetterheadSize = size(frame.letterheadTopPNG, frame.letterheadTopAspect, frame.letterheadTopScale)
        bottomLetterheadSize = size(frame.letterheadBottomPNG, frame.letterheadBottomAspect, frame.letterheadBottomScale)
        letterheadOnAllPages = frame.letterheadAllPages
        topLetterheadOffset = CGFloat(frame.letterheadTopOffset)
        bottomLetterheadOffset = CGFloat(frame.letterheadBottomOffset)
    }

    // MARK: - Letterhead images

    private func showsLetterhead(_ size: CGSize, bodyPage: Int) -> Bool {
        size.height > 0 && (letterheadOnAllPages || bodyPage == 0)
    }

    /// Top banner, centered and touching the top edge.
    func topLetterheadRect(bodyPage: Int) -> CGRect? {
        guard showsLetterhead(topLetterheadSize, bodyPage: bodyPage) else { return nil }
        return CGRect(x: (pageSize.width - topLetterheadSize.width) / 2, y: topLetterheadOffset,
                      width: topLetterheadSize.width, height: topLetterheadSize.height)
    }

    /// Bottom bar, centered and touching the bottom edge.
    func bottomLetterheadRect(bodyPage: Int) -> CGRect? {
        guard showsLetterhead(bottomLetterheadSize, bodyPage: bodyPage) else { return nil }
        return CGRect(x: (pageSize.width - bottomLetterheadSize.width) / 2,
                      y: pageSize.height - bottomLetterheadSize.height + bottomLetterheadOffset,
                      width: bottomLetterheadSize.width, height: bottomLetterheadSize.height)
    }

    /// Top margin of a page, pushed down below the letterhead banner when there is one.
    func effectiveMarginTop(bodyPage: Int) -> CGFloat {
        guard let banner = topLetterheadRect(bodyPage: bodyPage) else { return marginTop }
        return max(marginTop, banner.maxY + Self.letterheadGap)
    }

    /// Bottom margin of a page, raised above the contact bar when there is one.
    func effectiveMarginBottom(bodyPage: Int) -> CGFloat {
        guard let bar = bottomLetterheadRect(bodyPage: bodyPage) else { return marginBottom }
        return max(marginBottom, pageSize.height - bar.minY + Self.letterheadGap)
    }

    func headerTop(bodyPage: Int) -> CGFloat {
        guard let banner = topLetterheadRect(bodyPage: bodyPage) else { return headerTop }
        return max(headerTop, banner.maxY + Self.letterheadGap)
    }

    static func addresseeLineHeight(fontSize: Double) -> CGFloat {
        CGFloat(fontSize) * 1.9
    }

    static func addresseeHeight(for report: Report) -> CGFloat {
        let addressee = report.addressee
        guard report.kind == .text, addressee.isEnabled else { return 0 }
        var lines = 0
        if !addressee.recipientTitle.trimmed.isEmpty { lines += 1 }
        if !addressee.recipientName.trimmed.isEmpty || (addressee.showHonorific && !addressee.honorific.trimmed.isEmpty) { lines += 1 }
        if addressee.showGreeting && !addressee.greeting.trimmed.isEmpty { lines += 1 }
        guard lines > 0 else { return 0 }
        return CGFloat(lines) * addresseeLineHeight(fontSize: report.addresseeFontSize) + 14
    }

    /// Mark line: right under the letterhead, centered, above the addressee and greeting.
    var markRect: CGRect {
        CGRect(x: marginHorizontal, y: contentTop(bodyPage: 0), width: contentWidth, height: markHeight)
    }

    var addresseeRect: CGRect {
        CGRect(x: marginHorizontal, y: contentTop(bodyPage: 0) + markHeight, width: contentWidth, height: addresseeHeight)
    }

    static let employeeRowHeight: CGFloat = 112

    /// One row per two employees (right & left); a single employee is centered.
    static func signatureHeight(for footer: FooterSettings) -> CGFloat {
        let count = footer.employees.count
        let rows = count == 0 ? 0 : (count + 1) / 2
        let employeesHeight = CGFloat(rows) * employeeRowHeight
        let stampHeight: CGFloat = footer.stampPNG == nil ? 0 : 110
        let height = max(employeesHeight, stampHeight)
        return height > 0 ? height + 8 : 0
    }

    var footerHeight: CGFloat { reservesFooter ? 26 : 0 }

    var contentWidth: CGFloat { pageSize.width - marginHorizontal * 2 }

    func hasHeader(bodyPage: Int) -> Bool {
        headerEnabled && (headerOnAllPages || bodyPage == 0)
    }

    func headerRect(bodyPage: Int) -> CGRect {
        CGRect(x: marginHorizontal, y: headerTop(bodyPage: bodyPage), width: contentWidth, height: headerHeight)
    }

    /// Top of the writable area (below the letterhead when it is shown on this page).
    func contentTop(bodyPage: Int) -> CGFloat {
        let top = effectiveMarginTop(bodyPage: bodyPage)
        guard hasHeader(bodyPage: bodyPage) else { return top }
        return max(top, headerTop(bodyPage: bodyPage) + headerHeight + headerGap)
    }

    func bodyRect(bodyPage: Int) -> CGRect {
        let top = contentTop(bodyPage: bodyPage) + (bodyPage == 0 ? markHeight + addresseeHeight : 0)
        let bottom = pageSize.height - effectiveMarginBottom(bodyPage: bodyPage) - footerHeight
        return CGRect(x: marginHorizontal, y: top, width: contentWidth, height: max(bottom - top, 40))
    }

    func footerRect(bodyPage: Int) -> CGRect {
        CGRect(x: marginHorizontal, y: pageSize.height - effectiveMarginBottom(bodyPage: bodyPage) - footerHeight + 8,
               width: contentWidth, height: 18)
    }
}

extension PageLayoutSpec {
    /// Approximate lines per page for fixed (Word-like) spacing; nil for custom spacing.
    static func estimatedLines(for report: Report) -> (first: Int, other: Int)? {
        guard let lineHeight = report.textStyle.fixedLineHeight(forFontSize: report.textStyle.fontSize), lineHeight > 0 else {
            return nil
        }
        let spec = PageLayoutSpec(report: report)
        let first = Int(spec.bodyRect(bodyPage: 0).height / lineHeight)
        let other = Int(spec.bodyRect(bodyPage: 1).height / lineHeight)
        return (first, other)
    }
}
