import UIKit

/// Forces a new page (text container) at every U+000C character.
final class PageBreakLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length else { return action }
        if (storage.string as NSString).character(at: charIndex) == BodyDocument.pageBreakUnit {
            return .containerBreak
        }
        return action
    }
}

/// Result of laying out the body across A4 pages with TextKit.
/// Holds the TextKit objects alive so pages can be drawn (screen or PDF) without re-layout.
@MainActor
final class PaginationResult {
    enum PageKind: Equatable {
        case cover
        case body(Int)
    }

    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let containers: [NSTextContainer]
    let spec: PageLayoutSpec
    let hasCover: Bool
    /// True when the last text page has no room for the signature block and an extra page is appended.
    let signatureOnExtraPage: Bool
    private let delegateBox: PageBreakLayoutDelegate

    init(textStorage: NSTextStorage, layoutManager: NSLayoutManager, containers: [NSTextContainer],
         spec: PageLayoutSpec, hasCover: Bool, signatureOnExtraPage: Bool, delegate: PageBreakLayoutDelegate) {
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.containers = containers
        self.spec = spec
        self.hasCover = hasCover
        self.signatureOnExtraPage = signatureOnExtraPage
        self.delegateBox = delegate
    }

    var bodyPageCount: Int { max(containers.count, 1) + (signatureOnExtraPage ? 1 : 0) }
    var totalPages: Int { (hasCover ? 1 : 0) + bodyPageCount }
    var lastBodyPage: Int { bodyPageCount - 1 }
    var firstBodyPhysicalPage: Int { hasCover ? 1 : 0 }

    func kind(ofPage page: Int) -> PageKind {
        if hasCover { return page == 0 ? .cover : .body(page - 1) }
        return .body(page)
    }

    func physicalPage(forBodyPage bodyPage: Int) -> Int {
        bodyPage + (hasCover ? 1 : 0)
    }

    func glyphRange(forBodyPage bodyPage: Int) -> NSRange? {
        guard bodyPage >= 0, bodyPage < containers.count else { return nil }
        return layoutManager.glyphRange(for: containers[bodyPage])
    }

    func bodyPage(forCharacterAt location: Int) -> Int {
        guard textStorage.length > 0, !containers.isEmpty else { return 0 }
        let index = min(max(location, 0), textStorage.length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        guard glyph < layoutManager.numberOfGlyphs,
              let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
              let page = containers.firstIndex(where: { $0 === container }) else {
            return containers.count - 1
        }
        return page
    }
}

@MainActor
enum Paginator {
    static let maxPages = 300

    /// - Parameters:
    ///   - boxes: evidence boxes (A4 points); their pages always exist and the signatures avoid them.
    ///   - wrapsText: whether body text flows around the boxes (text reports).
    static func paginate(
        _ text: NSAttributedString,
        spec: PageLayoutSpec,
        hasCover: Bool,
        boxes: [EvidenceLayout.Placement] = [],
        wrapsText: Bool = true,
        minimumPages: Int = 1
    ) -> PaginationResult {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let delegate = PageBreakLayoutDelegate()
        layoutManager.delegate = delegate
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        var emptyStreak = 0

        func addContainer() {
            let index = containers.count
            let rect = spec.bodyRect(bodyPage: index)
            let container = NSTextContainer(size: rect.size)
            container.lineFragmentPadding = 0
            if wrapsText {
                container.exclusionPaths = boxes.filter { $0.page == index }.compactMap { box in
                    let local = box.rect
                        .insetBy(dx: -EvidenceLayout.textMargin, dy: -EvidenceLayout.textMargin)
                        .offsetBy(dx: -rect.minX, dy: -rect.minY)
                        .intersection(CGRect(origin: .zero, size: rect.size))
                    return local.isNull || local.width <= 0 || local.height <= 0 ? nil : UIBezierPath(rect: local)
                }
            }
            layoutManager.addTextContainer(container)
            containers.append(container)
        }

        while containers.count < maxPages {
            addContainer()

            let range = layoutManager.glyphRange(for: containers[containers.count - 1])
            let total = layoutManager.numberOfGlyphs
            if total == 0 || NSMaxRange(range) >= total { break }

            // A line taller than a page (e.g. a huge font) can never fit: stop instead of looping forever.
            if range.length == 0 {
                emptyStreak += 1
                if emptyStreak >= 3 { break }
            } else {
                emptyStreak = 0
            }
        }

        // Make sure the page holding the evidence, and pages the user added, exist even when empty.
        let lastBoxPage = boxes.map(\.page).max() ?? 0
        while containers.count <= lastBoxPage && containers.count < maxPages {
            addContainer()
        }
        while containers.count < minimumPages && containers.count < maxPages {
            addContainer()
        }

        var needsExtraPage = false
        if spec.signatureBlockHeight > 0, let last = containers.last {
            let lastIndex = containers.count - 1
            let body = spec.bodyRect(bodyPage: lastIndex)
            // Lowest point taken on the last page: its text, or an evidence box.
            var occupied = layoutManager.usedRect(for: last).maxY
            for box in boxes where box.page == lastIndex {
                occupied = max(occupied, box.rect.maxY - body.minY)
            }
            needsExtraPage = body.height - occupied < spec.signatureBlockHeight + 9
        }

        return PaginationResult(
            textStorage: storage,
            layoutManager: layoutManager,
            containers: containers,
            spec: spec,
            hasCover: hasCover,
            signatureOnExtraPage: needsExtraPage,
            delegate: delegate
        )
    }
}
