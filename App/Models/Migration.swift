import UIKit

/// Converts reports saved by versions 1.x (one text flowing across pages, page breaks,
/// page-indexed evidence and text boxes) into version 2 independent pages.
@MainActor
enum ReportMigration {
    static func upgraded(_ report: Report) -> Report {
        guard report.pagesStorage == nil else { return report }

        var result = report
        let settings = report.textStyle
        let full = BodyStyler.attributedString(from: report.body, settings: settings)
        // Compute old layout with the pages that will exist (no elements yet).
        var probe = report
        probe.pagesStorage = [ReportPage()]
        let spec = PageLayoutSpec(report: probe)

        // 1. Text: split at page breaks, then by what fits on each page.
        var texts: [NSAttributedString] = []
        let string = full.string as NSString
        var start = 0
        var sections: [NSRange] = []
        for index in 0..<string.length where string.character(at: index) == BodyDocument.pageBreakUnit {
            sections.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        sections.append(NSRange(location: start, length: string.length - start))
        for section in sections {
            texts += split(full.attributedSubstring(from: section), spec: spec, firstPage: texts.count)
        }

        var pages = texts.map { text in
            ReportPage(body: BodyStyler.document(from: trimmedLeadingNewlines(text), settings: settings))
        }
        if pages.isEmpty { pages = [ReportPage()] }

        func ensurePage(_ index: Int) {
            while pages.count <= index { pages.append(ReportPage()) }
        }

        // 2. Evidence boxes and text boxes keep their page and position.
        for block in report.evidenceBlocks where block.isVisible {
            let page = max(block.page, 0)
            ensurePage(page)
            var current = result
            current.pagesStorage = pages
            let rect = block.rect ?? DocumentLayout.defaultRect(for: .evidence, report: current, spec: spec, page: page)
            pages[page].elements.append(PageElement(kind: .evidence, rect: rect, evidence: block))
        }
        for box in report.textBoxes {
            let page = max(box.page, 0)
            ensurePage(page)
            pages[page].elements.append(PageElement(kind: .text, rect: box.rect, text: box))
        }
        ensurePage(report.minimumPages - 1)

        // 3. Clear version 1 storage.
        result.pagesStorage = pages
        result.body = BodyDocument()
        result.evidenceBlocksStorage = nil
        result.evidenceStorage = nil
        result.textBoxesStorage = nil
        result.minimumPagesValue = nil
        result.cover.isEnabled = false
        result.footer.resetPositions()
        return result
    }

    /// Splits text into page-sized pieces using the writing area of each page.
    private static func split(_ text: NSAttributedString, spec: PageLayoutSpec, firstPage: Int) -> [NSAttributedString] {
        guard text.length > 0 else { return [NSAttributedString()] }
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)

        var pieces: [NSAttributedString] = []
        var emptyStreak = 0
        while pieces.count < 300 {
            let size = spec.bodyRect(bodyPage: firstPage + pieces.count).size
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let glyphs = layoutManager.glyphRange(for: container)
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            pieces.append(text.attributedSubstring(from: characters))
            if NSMaxRange(glyphs) >= layoutManager.numberOfGlyphs { break }
            if glyphs.length == 0 {
                emptyStreak += 1
                if emptyStreak >= 3 { break }
            } else {
                emptyStreak = 0
            }
        }
        return pieces
    }

    private static func trimmedLeadingNewlines(_ text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        var start = 0
        while start < string.length, string.character(at: start) == 0x0A { start += 1 }
        return start == 0 ? text : text.attributedSubstring(from: NSRange(location: start, length: string.length - start))
    }
}
