import SwiftUI
import UIKit

// MARK: - Draggable handle

/// Transparent frame over an element on the page. Tap selects; when selected it can be dragged and
/// resized from its corner knob. Unselected handles never block scrolling.
@MainActor
final class ElementHandleView: UIView, UIGestureRecognizerDelegate {
    let key: String
    var minimumSize = CGSize(width: 40, height: 30)
    var keepsSquare = false
    var isSelectedHandle = false { didSet { updateAppearance() } }
    var tint: UIColor = .systemBlue { didSet { updateAppearance() } }

    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    /// Live frame while dragging (page coordinates).
    var onLiveChange: ((CGRect) -> Void)?
    /// Final frame when the finger lifts (page coordinates).
    var onCommit: ((CGRect) -> Void)?

    private let border = CAShapeLayer()
    private let knob = UIView()
    private var startFrame: CGRect = .zero
    private let knobSize: CGFloat = 26

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        backgroundColor = .clear
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 2
        border.lineDashPattern = [6, 4]
        layer.addSublayer(border)

        knob.layer.cornerRadius = knobSize / 2
        knob.layer.borderColor = UIColor.white.cgColor
        knob.layer.borderWidth = 2
        addSubview(knob)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        addGestureRecognizer(doubleTap)

        let move = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        move.delegate = self
        addGestureRecognizer(move)

        let resize = UIPanGestureRecognizer(target: self, action: #selector(resized(_:)))
        knob.addGestureRecognizer(resize)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.frame = bounds
        border.path = UIBezierPath(roundedRect: bounds, cornerRadius: 6).cgPath
        knob.frame = CGRect(x: bounds.maxX - knobSize / 2, y: bounds.maxY - knobSize / 2, width: knobSize, height: knobSize)
    }

    private func updateAppearance() {
        border.strokeColor = tint.cgColor
        border.isHidden = !isSelectedHandle
        knob.backgroundColor = tint
        knob.isHidden = !isSelectedHandle
        backgroundColor = isSelectedHandle ? tint.withAlphaComponent(0.08) : .clear
    }

    // The knob sits half outside the frame: let it receive touches.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isSelectedHandle && knob.frame.insetBy(dx: -10, dy: -10).contains(point) { return true }
        return super.point(inside: point, with: event)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer { return isSelectedHandle }
        return true
    }

    @objc private func tapped() { onTap?() }
    @objc private func doubleTapped() { onDoubleTap?() }

    private var pageBounds: CGRect {
        (superview?.bounds ?? CGRect(origin: .zero, size: A4.size)).insetBy(dx: 4, dy: 4)
    }

    @objc private func moved(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            startFrame = frame
        case .changed:
            let translation = gesture.translation(in: superview)
            var next = startFrame.offsetBy(dx: translation.x, dy: translation.y)
            next.origin.x = min(max(next.minX, pageBounds.minX), pageBounds.maxX - next.width)
            next.origin.y = min(max(next.minY, pageBounds.minY), pageBounds.maxY - next.height)
            frame = next
            onLiveChange?(next)
        case .ended, .cancelled:
            onCommit?(frame)
        default:
            break
        }
    }

    @objc private func resized(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            startFrame = frame
        case .changed:
            let translation = gesture.translation(in: superview)
            var width = max(startFrame.width + translation.x, minimumSize.width)
            var height = max(startFrame.height + translation.y, minimumSize.height)
            if keepsSquare {
                let side = max(width, height)
                width = side
                height = side
            }
            width = min(width, pageBounds.maxX - startFrame.minX)
            height = min(height, pageBounds.maxY - startFrame.minY)
            let next = CGRect(origin: startFrame.origin, size: CGSize(width: width, height: height))
            frame = next
            onLiveChange?(next)
        case .ended, .cancelled:
            onCommit?(frame)
        default:
            break
        }
    }
}

// MARK: - One page

/// One A4 page in the editor: drawn page (without body text) + its own editable text + handles.
@MainActor
final class PageSheetView: UIView {
    let pageID: UUID
    let background = PageCanvasView(frame: .zero)
    let textView = UITextView(usingTextLayoutManager: false)
    let overflowButton = UIButton(type: .system)
    var handles: [String: ElementHandleView] = [:]
    var appliedRevision = -1
    var baseExclusions: [String: CGRect] = [:]
    var textArea: CGRect = .zero
    private var appliedExclusions: [CGRect] = []

    init(pageID: UUID) {
        self.pageID = pageID
        super.init(frame: CGRect(origin: .zero, size: A4.size))
        backgroundColor = .white
        semanticContentAttribute = .forceLeftToRight
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        background.frame = bounds
        addSubview(background)

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
        addSubview(textView)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "exclamationmark.triangle.fill")
        config.imagePadding = 6
        config.attributedTitle = AttributedString("النص أطول من الصفحة — اضغط لنقل الزائد لصفحة جديدة",
                                                  attributes: AttributeContainer([.font: UIFont.boldSystemFont(ofSize: 12)]))
        overflowButton.configuration = config
        overflowButton.isHidden = true
        addSubview(overflowButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Text flows around elements: exclusion paths in text-view coordinates.
    func applyExclusions() {
        let rects = baseExclusions.keys.sorted().compactMap { baseExclusions[$0] }
            .map { $0.insetBy(dx: -DocumentLayout.elementMargin, dy: -DocumentLayout.elementMargin) }
        // Re-laying out text on every keystroke is costly: only update when areas really changed.
        guard rects != appliedExclusions else { return }
        appliedExclusions = rects
        textView.textContainer.exclusionPaths = DocumentLayout.localPaths(rects, in: textArea)
    }
}

// MARK: - The canvas

/// All pages stacked vertically in a zoomable scroll view.
@MainActor
final class DocumentCanvasView: UIView, UIScrollViewDelegate, UITextViewDelegate {
    let scrollView = UIScrollView()
    let contentView = UIView()
    private(set) var pageViews: [PageSheetView] = []
    weak var viewModel: ReportEditorViewModel?
    var tint: UIColor = .systemBlue
    var spellCheck = true
    var keyboardToolbar: UIView?
    var onEdit: ((ReportEditorViewModel.Selection) -> Void)?

    private var didInitialZoom = false
    private var fitScale: CGFloat = 0.6
    private var lastVisiblePage = -1
    static let gap: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemGray5
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.3
        scrollView.maximumZoomScale = 3
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.semanticContentAttribute = .forceLeftToRight
        addSubview(scrollView)
        contentView.semanticContentAttribute = .forceLeftToRight
        scrollView.addSubview(contentView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        contentView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        // Tapping empty page space (not text, not a handle) clears the selection.
        let point = gesture.location(in: contentView)
        if let hit = contentView.hitTest(point, with: nil), hit is ElementHandleView || hit.superview is ElementHandleView {
            return
        }
        if viewModel?.selection != nil { viewModel?.selection = nil }
    }

    private var activeTextView: UITextView? {
        pageViews.first { $0.textView.isFirstResponder }?.textView
    }

    // MARK: Zoom

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
        fitScale = min((bounds.width - 20) / A4.size.width, 1.4)
        scrollView.minimumZoomScale = fitScale * 0.6
        scrollView.setZoomScale(fitScale, animated: animated)
        updateRenderingScale()
    }

    func toggleZoom() {
        if scrollView.zoomScale > fitScale * 1.2 {
            fitWidth(animated: true)
        } else {
            scrollView.setZoomScale(max(fitScale * 1.7, 1), animated: true)
            scrollCaretIntoView()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateRenderingScale()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let zoom = max(scrollView.zoomScale, 0.01)
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / zoom
        let page = min(max(Int(centerY / (A4.size.height + Self.gap)), 0), max(pageViews.count - 1, 0))
        if page != lastVisiblePage {
            lastVisiblePage = page
            if viewModel?.visiblePageIndex != page { viewModel?.visiblePageIndex = page }
        }
    }

    private func centerContent() {
        let horizontal = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: 56, left: horizontal, bottom: 90, right: horizontal)
    }

    private func updateRenderingScale() {
        let screen = window?.screen.scale ?? 3
        let zoom = scrollView.zoomScale
        let pageScale = min(max(screen * zoom, 1), 3)
        let textScale = min(max(screen * zoom, 1), 6)
        for page in pageViews {
            if page.background.contentScaleFactor != pageScale {
                page.background.contentScaleFactor = pageScale
                page.background.setNeedsDisplay()
            }
            Self.apply(scale: textScale, to: page.textView)
        }
    }

    private static func apply(scale: CGFloat, to view: UIView) {
        view.contentScaleFactor = scale
        view.layer.contentsScale = scale
        view.subviews.forEach { apply(scale: scale, to: $0) }
        view.setNeedsDisplay()
    }

    func scrollToPage(_ index: Int) {
        guard pageViews.indices.contains(index) else { return }
        let rect = pageViews[index].frame
        let zoom = scrollView.zoomScale
        let y = rect.minY * zoom - scrollView.contentInset.top
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: max(y, -scrollView.contentInset.top)), animated: true)
    }

    func scrollCaretIntoView() {
        guard let textView = activeTextView, let range = textView.selectedTextRange else { return }
        let caret = textView.caretRect(for: range.end)
        guard caret.origin.y.isFinite else { return }
        let rect = textView.convert(caret, to: scrollView).insetBy(dx: -24, dy: -60)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    // MARK: Applying state

    private var lastReport: Report?
    private weak var lastSnapshot: DocumentSnapshot?
    private var lastSelection: ReportEditorViewModel.Selection?
    private var lastRevision = -1

    func apply(force: Bool = false) {
        guard let vm = viewModel else { return }
        let report = vm.report
        if !force, lastReport == report, lastSnapshot === vm.snapshot, lastSelection == vm.selection,
           lastRevision == vm.textRevision {
            return
        }
        lastReport = report
        lastSnapshot = vm.snapshot
        lastSelection = vm.selection
        lastRevision = vm.textRevision

        syncPageViews(report.pages.map(\.id))

        let height = CGFloat(pageViews.count) * (A4.size.height + Self.gap) - Self.gap
        let size = CGSize(width: A4.size.width, height: max(height, A4.size.height))
        let zoom = scrollView.zoomScale
        if contentView.bounds.size != size {
            contentView.bounds = CGRect(origin: .zero, size: size)
            contentView.center = CGPoint(x: size.width * zoom / 2, y: size.height * zoom / 2)
            scrollView.contentSize = CGSize(width: size.width * zoom, height: size.height * zoom)
            centerContent()
        }

        let spec = vm.snapshot.spec
        let signature = DocumentLayout.signaturePlacement(report: report, spec: spec, pageCount: report.pages.count)
        for (index, pageView) in pageViews.enumerated() {
            pageView.frame = CGRect(x: 0, y: CGFloat(index) * (A4.size.height + Self.gap), width: A4.size.width, height: A4.size.height)
            configure(pageView, index: index, vm: vm, report: report, spec: spec, signature: signature)
        }
        updateRenderingScale()
    }

    private func syncPageViews(_ ids: [UUID]) {
        var existing = Dictionary(uniqueKeysWithValues: pageViews.map { ($0.pageID, $0) })
        var ordered: [PageSheetView] = []
        for id in ids {
            if let view = existing.removeValue(forKey: id) {
                ordered.append(view)
            } else {
                let view = PageSheetView(pageID: id)
                view.textView.delegate = self
                view.overflowButton.addAction(UIAction { [weak self, weak view] _ in
                    guard let self, let view, let index = self.pageViews.firstIndex(of: view) else { return }
                    self.viewModel?.moveOverflowToNewPage(index)
                }, for: .touchUpInside)
                contentView.addSubview(view)
                ordered.append(view)
            }
        }
        existing.values.forEach { $0.removeFromSuperview() }
        pageViews = ordered
    }

    private func configure(_ pageView: PageSheetView, index: Int, vm: ReportEditorViewModel, report: Report,
                           spec: PageLayoutSpec, signature: DocumentLayout.Placement?) {
        // Drawn page (frame, letterhead, fields, elements, signatures) without the body text.
        if vm.snapshot.pageCount == report.pages.count {
            pageView.background.update(page: index, snapshot: vm.snapshot, includeBody: false)
        }

        // Editable text, exactly over the page's writing area.
        let area = DocumentLayout.textArea(report: report, spec: spec, page: index)
        pageView.textArea = area
        if pageView.textView.frame != area {
            pageView.textView.frame = area
            pageView.textView.textContainer.size = CGSize(width: area.width, height: area.height)
        }
        let textView = pageView.textView
        textView.tintColor = tint
        textView.inputAccessoryView = keyboardToolbar
        let spelling: UITextSpellCheckingType = spellCheck ? .yes : .no
        if textView.spellCheckingType != spelling {
            textView.spellCheckingType = spelling
            textView.autocorrectionType = spellCheck ? .default : .no
        }
        if pageView.appliedRevision != vm.textRevision {
            pageView.appliedRevision = vm.textRevision
            let selected = textView.selectedRange
            let text = vm.attributedText(ofPage: index)
            textView.attributedText = text
            textView.typingAttributes = vm.typingAttributes
            let location = min(selected.location, text.length)
            textView.selectedRange = NSRange(location: location, length: 0)
        }
        if textView.attributedText.length == 0 {
            textView.typingAttributes = vm.typingAttributes
        }

        // Handles for elements, signatures and logo.
        var wanted: [String: (rect: CGRect, minimum: CGSize, square: Bool, selection: ReportEditorViewModel.Selection)] = [:]
        for element in report.pages[index].elements {
            wanted[element.id.uuidString] = (element.rect, element.minimumSize, false, .element(element.id))
        }
        if let signature, signature.page == index {
            wanted["signatures"] = (signature.rect, CGSize(width: 120, height: 60), false, .signatures)
        }
        if let logo = vm.logoBox(onPage: index) {
            wanted["logo"] = (logo, CGSize(width: 40, height: 40), true, .logo)
        }

        for key in pageView.handles.keys where wanted[key] == nil {
            pageView.handles.removeValue(forKey: key)?.removeFromSuperview()
        }
        var exclusions: [String: CGRect] = [:]
        for (key, item) in wanted {
            let handle: ElementHandleView
            if let existing = pageView.handles[key] {
                handle = existing
            } else {
                handle = ElementHandleView(key: key)
                pageView.addSubview(handle)
                pageView.handles[key] = handle
            }
            let selection = item.selection
            handle.frame = item.rect
            handle.minimumSize = item.minimum
            handle.keepsSquare = item.square
            handle.tint = tint
            handle.isSelectedHandle = vm.selection == selection
            handle.onTap = { [weak vm] in
                vm?.selection = selection
                KeyboardHelper.dismiss()
            }
            handle.onDoubleTap = { [weak self, weak vm] in
                vm?.selection = selection
                self?.onEdit?(selection)
            }
            handle.onLiveChange = { [weak pageView] rect in
                guard let pageView, key != "logo" else { return }
                pageView.baseExclusions[key] = rect
                pageView.applyExclusions()
            }
            handle.onCommit = { [weak vm] rect in
                guard let vm else { return }
                switch selection {
                case .element(let id): vm.setElementRect(id, rect)
                case .signatures: vm.setSignatureRect(rect)
                case .logo: vm.setLogoFrame(rect, onPage: index)
                }
            }
            if key != "logo" { exclusions[key] = item.rect }
        }
        pageView.baseExclusions = exclusions
        pageView.applyExclusions()
        // Keep handles above text so they can be tapped.
        pageView.handles.values.forEach { pageView.bringSubviewToFront($0) }

        // Overflow warning just below the writing area.
        let overflow = vm.snapshot.texts.indices.contains(index) && vm.snapshot.texts[index].overflowLocation != nil
            && vm.snapshot.pageCount == report.pages.count
        pageView.overflowButton.isHidden = !overflow
        if overflow {
            let size = pageView.overflowButton.intrinsicContentSize
            let y = min(area.maxY + 4, A4.size.height - size.height - 4)
            pageView.overflowButton.frame = CGRect(x: (A4.size.width - size.width) / 2, y: y, width: size.width, height: size.height)
            pageView.bringSubviewToFront(pageView.overflowButton)
        }
    }

    // MARK: UITextViewDelegate

    private func pageView(for textView: UITextView) -> PageSheetView? {
        pageViews.first { $0.textView === textView }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard let page = pageView(for: textView) else { return }
        viewModel?.beganEditing(page: page.pageID, textView: textView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.scrollCaretIntoView() }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let page = pageView(for: textView) else { return }
        viewModel?.pageTextChanged(page.pageID, textView.attributedText)
        DispatchQueue.main.async { [weak self] in self?.scrollCaretIntoView() }
    }
}

// MARK: - Keyboard toolbar

/// Formatting tools shown above the keyboard while writing on a page.
@MainActor
enum KeyboardToolbarFactory {
    static func make(richText: RichTextController, onAI: @escaping () -> Void, onFormat: @escaping () -> Void) -> UIView {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        toolbar.semanticContentAttribute = .forceRightToLeft

        func item(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> UIBarButtonItem {
            let button = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { _ in action() })
            button.accessibilityLabel = label
            return button
        }

        let alignMenu = UIMenu(children: ParagraphAlignment.allCases.map { alignment in
            UIAction(title: alignment.title, image: UIImage(systemName: alignment.systemImage)) { _ in
                richText.setAlignment(alignment)
            }
        })
        let align = UIBarButtonItem(image: UIImage(systemName: "text.alignright"), menu: alignMenu)
        align.accessibilityLabel = "المحاذاة"

        toolbar.items = [
            item("sparkles", "الذكاء الاصطناعي", onAI),
            .flexibleSpace(),
            item("bold", "عريض") { richText.toggleBold() },
            item("underline", "تسطير") { richText.toggleUnderline() },
            item("textformat.size.larger", "تكبير") { richText.adjustSelectionSize(by: 1) },
            item("textformat.size.smaller", "تصغير") { richText.adjustSelectionSize(by: -1) },
            align,
            item("textformat", "تنسيق الخط", onFormat),
            .flexibleSpace(),
            item("keyboard.chevron.compact.down", "إخفاء لوحة المفاتيح") { KeyboardHelper.dismiss() }
        ]
        toolbar.sizeToFit()
        return toolbar
    }
}

// MARK: - SwiftUI bridge

struct DocumentCanvas: UIViewRepresentable {
    @ObservedObject var vm: ReportEditorViewModel
    let tint: UIColor
    let spellCheck: Bool
    let onAI: () -> Void
    let onFormat: () -> Void
    let onEdit: (ReportEditorViewModel.Selection) -> Void
    let scrollRequest: Int?

    func makeUIView(context: Context) -> DocumentCanvasView {
        let view = DocumentCanvasView(frame: .zero)
        view.viewModel = vm
        view.tint = tint
        view.spellCheck = spellCheck
        view.keyboardToolbar = KeyboardToolbarFactory.make(richText: vm.richText, onAI: onAI, onFormat: onFormat)
        view.onEdit = onEdit
        vm.richText.zoomToggle = { [weak view] in view?.toggleZoom() }
        view.apply(force: true)
        return view
    }

    func updateUIView(_ view: DocumentCanvasView, context: Context) {
        view.onEdit = onEdit
        let styleChanged = view.tint != tint || view.spellCheck != spellCheck
        view.tint = tint
        view.spellCheck = spellCheck
        view.apply(force: styleChanged)
        if let request = scrollRequest, context.coordinator.lastScrollRequest != request {
            context.coordinator.lastScrollRequest = request
            DispatchQueue.main.async { view.scrollToPage(vm.visiblePageIndex) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastScrollRequest: Int?
    }
}
