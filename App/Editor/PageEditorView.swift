import SwiftUI
import UIKit

/// On-page editor: the real A4 pages (frame, letterhead, addressee, signatures, page numbers)
/// with one editable text view laid over their writing areas. The text view is exactly as wide as
/// the page's text area and uses the same attributes as the PDF, so every line ends where it will
/// in the exported file. Text flows from page to page by excluding the space between writing areas.
@MainActor
final class PageEditorView: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let pagesView = UIView()
    let textView = UITextView(usingTextLayoutManager: false)

    private var canvases: [PageCanvasView] = []
    private var spec: PageLayoutSpec?
    private var context: PageRenderContext?
    private var pageCount = 1
    private var didInitialZoom = false
    private var fitScale: CGFloat = 0.6
    private var reflowWork: DispatchWorkItem?

    static let pageGap: CGFloat = 20
    private static let maxPages = 300

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGray5

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.3
        scrollView.maximumZoomScale = 3
        scrollView.bouncesZoom = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.semanticContentAttribute = .forceLeftToRight
        addSubview(scrollView)

        pagesView.backgroundColor = .clear
        pagesView.semanticContentAttribute = .forceLeftToRight
        scrollView.addSubview(pagesView)

        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        textView.overrideUserInterfaceStyle = .light
        textView.textColor = .black
        textView.semanticContentAttribute = .forceRightToLeft
        textView.allowsEditingTextAttributes = true
        textView.adjustsFontForContentSizeCategory = false
        textView.layoutManager.usesFontLeading = true
        textView.layoutManager.delegate = pageBreakDelegate
        pagesView.addSubview(textView)
    }

    /// Page breaks (U+000C) are handled with exclusion areas, so they must not break containers here.
    private let pageBreakDelegate = InlinePageBreakDelegate()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout & zoom

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        if !didInitialZoom, bounds.width > 0 {
            didInitialZoom = true
            fitWidth(animated: false)
        }
        centerContent()
    }

    func fitWidth(animated: Bool) {
        guard bounds.width > 0 else { return }
        fitScale = (bounds.width - 16) / A4.size.width
        scrollView.minimumZoomScale = fitScale * 0.6
        scrollView.setZoomScale(fitScale, animated: animated)
        updateRenderingScale()
    }

    /// Toggles between "whole page width" and a comfortable reading size.
    func toggleZoom() {
        let reading = max(fitScale * 1.6, 1)
        if scrollView.zoomScale > fitScale * 1.2 {
            fitWidth(animated: true)
        } else {
            scrollView.setZoomScale(reading, animated: true)
            scrollCaretIntoView()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pagesView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateRenderingScale()
    }

    private func centerContent() {
        let contentSize = scrollView.contentSize
        let horizontal = max((scrollView.bounds.width - contentSize.width) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: 10, left: horizontal, bottom: 40, right: horizontal)
    }

    /// Re-renders text and pages at the current zoom so they stay sharp without wasting memory.
    private func updateRenderingScale() {
        let screen = window?.screen.scale ?? 3
        let zoom = scrollView.zoomScale
        let pageScale = min(max(screen * zoom, 1), 3)
        for canvas in canvases where canvas.contentScaleFactor != pageScale {
            canvas.contentScaleFactor = pageScale
            canvas.setNeedsDisplay()
        }
        let textScale = min(max(screen * zoom, 1), 6)
        Self.apply(scale: textScale, to: textView)
    }

    private static func apply(scale: CGFloat, to view: UIView) {
        view.contentScaleFactor = scale
        view.layer.contentsScale = scale
        view.subviews.forEach { apply(scale: scale, to: $0) }
        view.setNeedsDisplay()
    }

    // MARK: - Pages

    private func pageTop(_ index: Int) -> CGFloat {
        CGFloat(index) * (A4.size.height + Self.pageGap)
    }

    func configure(spec: PageLayoutSpec, context: PageRenderContext) {
        self.spec = spec
        self.context = context
        reflow()
    }

    private func layoutPages(_ count: Int) {
        guard let spec, let context else { return }
        pageCount = count

        let size = CGSize(width: A4.size.width, height: pageTop(count) - Self.pageGap)
        let zoom = scrollView.zoomScale
        if pagesView.bounds.size != size {
            pagesView.bounds = CGRect(origin: .zero, size: size)
            pagesView.center = CGPoint(x: size.width * zoom / 2, y: size.height * zoom / 2)
            scrollView.contentSize = CGSize(width: size.width * zoom, height: size.height * zoom)
            centerContent()
        }

        while canvases.count < count {
            let canvas = PageCanvasView(frame: .zero)
            canvas.layer.shadowColor = UIColor.black.cgColor
            canvas.layer.shadowOpacity = 0.15
            canvas.layer.shadowRadius = 5
            canvas.layer.shadowOffset = CGSize(width: 0, height: 2)
            pagesView.insertSubview(canvas, belowSubview: textView)
            canvases.append(canvas)
        }
        while canvases.count > count {
            canvases.removeLast().removeFromSuperview()
        }
        for (index, canvas) in canvases.enumerated() {
            canvas.frame = CGRect(x: 0, y: pageTop(index), width: A4.size.width, height: A4.size.height)
            canvas.update(page: context.pagination.physicalPage(forBodyPage: index), context: context, includeBody: false)
        }
        updateRenderingScale()

        let top = spec.bodyRect(bodyPage: 0).minY
        let frame = CGRect(x: spec.marginHorizontal, y: top, width: spec.contentWidth, height: size.height - top)
        if textView.frame != frame {
            textView.frame = frame
            textView.textContainer.size = CGSize(width: frame.width, height: 10_000_000)
        }
    }

    // MARK: - Text flow

    func scheduleReflow() {
        reflowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reflow() }
        reflowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Places the gaps between pages (and after forced page breaks) as exclusion areas, adding or
    /// removing pages until the text fits. Iterates because exclusions move the text after them.
    func reflow() {
        guard let spec, let context else { return }
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        let minimumPages = max(context.pagination.bodyPageCount, 1)

        var count = max(pageCount, minimumPages)
        var breaks: [CGRect] = []
        layoutPages(count)

        for _ in 0..<10 {
            container.exclusionPaths = (gapRects(count, spec: spec) + breaks).map { UIBezierPath(rect: $0) }
            layoutManager.ensureLayout(for: container)

            let needed = max(pagesNeeded(spec: spec), minimumPages)
            let newBreaks = pageBreakRects(spec: spec, pageLimit: max(needed, count))
            if needed == count && newBreaks == breaks { break }
            if needed != count {
                count = needed
                layoutPages(count)
            }
            breaks = newBreaks
        }
    }

    /// Areas between the writing area of each page and the next, in text-container coordinates.
    private func gapRects(_ count: Int, spec: PageLayoutSpec) -> [CGRect] {
        let originY = textView.frame.minY
        var rects: [CGRect] = []
        for index in 0..<max(count - 1, 0) {
            let bottom = pageTop(index) + spec.bodyRect(bodyPage: index).maxY
            let nextTop = pageTop(index + 1) + spec.bodyRect(bodyPage: index + 1).minY
            rects.append(CGRect(x: 0, y: bottom - originY, width: spec.contentWidth, height: nextTop - bottom))
        }
        return rects
    }

    private func bodyPage(containingY y: CGFloat, spec: PageLayoutSpec, limit: Int) -> Int {
        var index = 0
        while index < limit - 1 && y > pageTop(index) + spec.bodyRect(bodyPage: index).maxY + 0.5 {
            index += 1
        }
        return index
    }

    private func pagesNeeded(spec: PageLayoutSpec) -> Int {
        let used = textView.layoutManager.usedRect(for: textView.textContainer)
        let bottom = textView.frame.minY + used.maxY
        return min(bodyPage(containingY: bottom - 0.5, spec: spec, limit: Self.maxPages) + 1, Self.maxPages)
    }

    /// For each forced page break, the rest of its page is excluded so the following text starts
    /// on the next page — exactly like the exported PDF.
    private func pageBreakRects(spec: PageLayoutSpec, pageLimit: Int) -> [CGRect] {
        let storage = textView.textStorage
        let string = storage.string as NSString
        let layoutManager = textView.layoutManager
        let originY = textView.frame.minY
        var rects: [CGRect] = []

        for index in 0..<string.length where string.character(at: index) == BodyDocument.pageBreakUnit {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            guard glyph < layoutManager.numberOfGlyphs else { continue }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let lineBottom = originY + line.maxY
            let page = bodyPage(containingY: lineBottom - 0.5, spec: spec, limit: pageLimit + 1)
            let pageBottom = pageTop(page) + spec.bodyRect(bodyPage: page).maxY
            if pageBottom - lineBottom > 0.5 {
                rects.append(CGRect(x: 0, y: line.maxY, width: spec.contentWidth, height: pageBottom - lineBottom))
            }
        }
        return rects
    }

    // MARK: - Caret

    func scrollCaretIntoView() {
        guard textView.isFirstResponder, let range = textView.selectedTextRange else { return }
        let caret = textView.caretRect(for: range.end)
        guard caret.origin.y.isFinite else { return }
        let rect = textView.convert(caret, to: scrollView).insetBy(dx: -24, dy: -48)
        scrollView.scrollRectToVisible(rect, animated: true)
    }
}

/// Keeps U+000C as an ordinary line break inside the single editing container.
final class InlinePageBreakDelegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length else { return action }
        if (storage.string as NSString).character(at: charIndex) == BodyDocument.pageBreakUnit {
            return .paragraphBreak
        }
        return action
    }
}

/// SwiftUI bridge for the on-page editor.
struct PageEditor: UIViewRepresentable {
    let controller: RichTextController
    let content: NSAttributedString
    let revision: Int
    let typingAttributes: [NSAttributedString.Key: Any]
    let tint: UIColor
    let spellCheck: Bool
    let context: PageRenderContext
    let report: Report

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> PageEditorView {
        let view = PageEditorView(frame: .zero)
        let textView = view.textView
        textView.delegate = context.coordinator
        textView.tintColor = tint
        textView.spellCheckingType = spellCheck ? .yes : .no
        textView.autocorrectionType = spellCheck ? .default : .no
        textView.attributedText = content
        textView.typingAttributes = typingAttributes
        context.coordinator.view = view
        context.coordinator.appliedRevision = revision
        controller.attach(textView)
        controller.zoomToggle = { [weak view] in view?.toggleZoom() }
        context.coordinator.lastReport = report
        context.coordinator.lastPagination = self.context.pagination
        view.configure(spec: PageLayoutSpec(report: report), context: self.context)
        return view
    }

    func updateUIView(_ view: PageEditorView, context: Context) {
        let textView = view.textView
        controller.attach(textView)
        controller.zoomToggle = { [weak view] in view?.toggleZoom() }
        textView.tintColor = tint

        let spelling: UITextSpellCheckingType = spellCheck ? .yes : .no
        if textView.spellCheckingType != spelling {
            textView.spellCheckingType = spelling
            textView.autocorrectionType = spellCheck ? .default : .no
            if textView.isFirstResponder { textView.reloadInputViews() }
        }

        var needsReflow = false
        if context.coordinator.appliedRevision != revision {
            context.coordinator.appliedRevision = revision
            let selection = textView.selectedRange
            textView.attributedText = content
            let location = min(selection.location, content.length)
            textView.selectedRange = NSRange(location: location, length: 0)
            if content.length == 0 { textView.typingAttributes = typingAttributes }
            needsReflow = true
        }

        if context.coordinator.lastReport != report || context.coordinator.lastPagination !== self.context.pagination {
            context.coordinator.lastReport = report
            context.coordinator.lastPagination = self.context.pagination
            view.configure(spec: PageLayoutSpec(report: report), context: self.context)
        } else if needsReflow {
            view.reflow()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: RichTextController
        weak var view: PageEditorView?
        var appliedRevision = -1
        var lastReport: Report?
        var lastPagination: PaginationResult?

        init(controller: RichTextController) {
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            controller.textDidChange(textView)
            view?.scheduleReflow()
            DispatchQueue.main.async { [weak self] in self?.view?.scrollCaretIntoView() }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            controller.selectionDidChange(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.view?.scrollCaretIntoView() }
        }
    }
}
