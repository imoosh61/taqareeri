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
    }

    static func addresseeLineHeight(fontSize: Double) -> CGFloat {
        CGFloat(fontSize) * 1.9
    }

    static func addresseeHeight(for report: Report) -> CGFloat {
        let addressee = report.addressee
        guard addressee.isEnabled else { return 0 }
        var lines = 0
        if !addressee.recipientTitle.trimmed.isEmpty { lines += 1 }
        if !addressee.recipientName.trimmed.isEmpty || (addressee.showHonorific && !addressee.honorific.trimmed.isEmpty) { lines += 1 }
        if addressee.showGreeting && !addressee.greeting.trimmed.isEmpty { lines += 1 }
        guard lines > 0 else { return 0 }
        return CGFloat(lines) * addresseeLineHeight(fontSize: report.addresseeFontSize) + 14
    }

    var addresseeRect: CGRect {
        return CGRect(x: marginHorizontal, y: contentTop(bodyPage: 0), width: contentWidth, height: addresseeHeight)
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

    var headerRect: CGRect {
        CGRect(x: marginHorizontal, y: headerTop, width: contentWidth, height: headerHeight)
    }

    /// Top of the writable area (below the letterhead when it is shown on this page).
    func contentTop(bodyPage: Int) -> CGFloat {
        hasHeader(bodyPage: bodyPage) ? max(marginTop, headerTop + headerHeight + headerGap) : marginTop
    }

    func bodyRect(bodyPage: Int) -> CGRect {
        let top = contentTop(bodyPage: bodyPage) + (bodyPage == 0 ? addresseeHeight : 0)
        let bottom = pageSize.height - marginBottom - footerHeight
        return CGRect(x: marginHorizontal, y: top, width: contentWidth, height: max(bottom - top, 40))
    }

    var footerRect: CGRect {
        CGRect(x: marginHorizontal, y: pageSize.height - marginBottom - footerHeight + 8, width: contentWidth, height: 18)
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
