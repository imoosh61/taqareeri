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
    let marginHorizontal: CGFloat = 56
    let marginTop: CGFloat = 46
    let marginBottom: CGFloat = 46
    let headerHeight: CGFloat = 132
    let headerGap: CGFloat = 12
    let headerEnabled: Bool
    let headerOnAllPages: Bool
    let reservesFooter: Bool
    /// Height reserved on the last page for signature & stamp (0 when disabled).
    let signatureBlockHeight: CGFloat

    init(report: Report) {
        headerEnabled = report.header.isEnabled
        headerOnAllPages = report.header.placement == .allPages
        reservesFooter = report.page.showPageNumbers
        signatureBlockHeight = report.footer.showSignatureBlock ? 132 : 0
    }

    var footerHeight: CGFloat { reservesFooter ? 26 : 0 }

    var contentWidth: CGFloat { pageSize.width - marginHorizontal * 2 }

    func hasHeader(bodyPage: Int) -> Bool {
        headerEnabled && (headerOnAllPages || bodyPage == 0)
    }

    var headerRect: CGRect {
        CGRect(x: marginHorizontal, y: marginTop, width: contentWidth, height: headerHeight)
    }

    func bodyRect(bodyPage: Int) -> CGRect {
        let top = marginTop + (hasHeader(bodyPage: bodyPage) ? headerHeight + headerGap : 0)
        let bottom = pageSize.height - marginBottom - footerHeight
        return CGRect(x: marginHorizontal, y: top, width: contentWidth, height: max(bottom - top, 40))
    }

    var footerRect: CGRect {
        CGRect(x: marginHorizontal, y: pageSize.height - marginBottom - footerHeight + 8, width: contentWidth, height: 18)
    }
}
