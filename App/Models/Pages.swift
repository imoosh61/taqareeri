import CoreGraphics
import Foundation

/// Something placed freely on a page: an evidence box or a text box.
/// Body text on the same page flows around it, so nothing overlaps.
struct PageElement: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case evidence, text, table
    }

    var id = UUID()
    var kind: Kind
    /// Position & size in A4 points.
    var rect: CGRect
    var evidence: EvidenceBlock?
    var text: TextBox?
    var table: TableBlock?

    static func evidence(rect: CGRect) -> PageElement {
        PageElement(kind: .evidence, rect: rect, evidence: EvidenceBlock())
    }

    static func text(rect: CGRect, content: String = "نص جديد") -> PageElement {
        PageElement(kind: .text, rect: rect, text: TextBox(text: content))
    }

    static func table(rect: CGRect) -> PageElement {
        PageElement(kind: .table, rect: rect, table: TableBlock())
    }

    var minimumSize: CGSize {
        switch kind {
        case .evidence: return CGSize(width: 90, height: 70)
        case .text: return TextBox.minimumSize
        case .table: return CGSize(width: 120, height: 40)
        }
    }

    /// Arabic name shown in menus.
    var title: String {
        switch kind {
        case .evidence: return "الشواهد"
        case .text: return "مربع النص"
        case .table: return "الجدول"
        }
    }
}

/// One independent page: its own text and its own elements. Pages never push content to each other.
struct ReportPage: Identifiable, Codable, Equatable {
    var id = UUID()
    var body = BodyDocument()
    var elements: [PageElement] = []

    var isEmpty: Bool { body.isEmpty && elements.isEmpty }
}

extension Report {
    /// The pages of the report (always at least one).
    var pages: [ReportPage] {
        get {
            if let pages = pagesStorage, !pages.isEmpty { return pages }
            return [ReportPage()]
        }
        set { pagesStorage = newValue.isEmpty ? [ReportPage()] : newValue }
    }

    /// Whether the names / signatures / stamp block is shown.
    var showsSignatures: Bool {
        footer.showSignatureBlock && (!footer.employees.isEmpty || footer.stampPNG != nil)
    }

    func pageIndex(of id: UUID) -> Int? {
        pages.firstIndex { $0.id == id }
    }

    /// Finds an element anywhere in the report.
    func locate(element id: UUID) -> (page: Int, element: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let elementIndex = page.elements.firstIndex(where: { $0.id == id }) {
                return (pageIndex, elementIndex)
            }
        }
        return nil
    }
}
