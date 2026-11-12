import Combine
import Foundation
import UIKit

/// Owns one report while it is edited: independent pages, elements placed on pages, the live
/// document snapshot used for drawing, autosave, images, formatting, AI and export.
@MainActor
final class ReportEditorViewModel: ObservableObject {
    /// What is selected on the canvas (for moving / resizing / editing).
    enum Selection: Equatable {
        case element(UUID)
        case signatures
        case logo
    }

    @Published var report: Report
    @Published private(set) var snapshot: DocumentSnapshot
    @Published private(set) var images: RenderImages
    @Published var selection: Selection?
    @Published private(set) var activePageID: UUID?
    @Published var visiblePageIndex = 0
    /// Bumped whenever page texts are changed from outside the text views (format, AI, split, style…).
    @Published private(set) var textRevision = 0
    @Published var logoRemovalMode: LogoBackgroundMode = .smart
    @Published private(set) var isProcessingImage = false
    @Published var errorMessage: String?
    @Published var notice: String?
    /// Description of the last undoable change (nil = nothing to undo).
    @Published private(set) var undoTitle: String?

    let richText = RichTextController()

    private let store: ReportStore
    private var appliedTextStyle: TextStyleSettings
    private var originalLogoData: Data?
    private var hasUnsavedChanges = false
    private var undoState: Report?
    private var cancellables = Set<AnyCancellable>()

    init(report: Report, store: ReportStore) {
        let upgraded = ReportMigration.upgraded(report)
        self.report = upgraded
        self.store = store
        self.appliedTextStyle = upgraded.textStyle
        let images = RenderImages(report: upgraded)
        self.images = images
        self.snapshot = DocumentSnapshot(report: upgraded, images: images)
        if upgraded != report { hasUnsavedChanges = true }
        configureRichText()
        bindPipelines()
    }

    // MARK: - Derived

    var typingAttributes: [NSAttributedString.Key: Any] {
        BodyStyler.typingAttributes(report.textStyle)
    }

    var pageCount: Int { report.pages.count }

    var activePageIndex: Int {
        activePageID.flatMap { report.pageIndex(of: $0) } ?? min(visiblePageIndex, pageCount - 1)
    }

    var activePageText: String {
        let index = activePageIndex
        return report.pages.indices.contains(index) ? report.pages[index].body.text : ""
    }

    func attributedText(ofPage index: Int) -> NSAttributedString {
        guard report.pages.indices.contains(index) else { return NSAttributedString() }
        return BodyStyler.attributedString(from: report.pages[index].body, settings: report.textStyle)
    }

    func pageLabel(_ index: Int) -> String {
        ArabicFormat.pageLabel(index + 1, of: pageCount, report.page.numerals)
    }

    // MARK: - Wiring

    private func configureRichText() {
        richText.settingsProvider = { [weak self] in self?.report.textStyle ?? TextStyleSettings() }
        richText.onTextChanged = { [weak self] text in
            guard let self, let id = self.activePageID else { return }
            self.pageTextChanged(id, text)
        }
    }

    private func bindPipelines() {
        // `$report` emits the new value *before* `report` is updated.
        $report
            .dropFirst()
            .sink { [weak self] newValue in self?.reportWillChange(to: newValue) }
            .store(in: &cancellables)

        $report
            .dropFirst()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildSnapshot() }
            .store(in: &cancellables)

        $report
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &cancellables)
    }

    private func reportWillChange(to newValue: Report) {
        hasUnsavedChanges = true
        if RenderImages.sources(of: newValue) != RenderImages.sources(of: report) {
            images = RenderImages(report: newValue)
        }
        if newValue.textStyle != appliedTextStyle {
            let old = appliedTextStyle
            appliedTextStyle = newValue.textStyle
            // Applied after this change has been stored.
            DispatchQueue.main.async { [weak self] in self?.restylePages(from: old, to: newValue.textStyle) }
        }
    }

    /// Keeps relative sizes when the base size changes and applies a new default alignment to all text.
    private func restylePages(from old: TextStyleSettings, to new: TextStyleSettings) {
        var pages = report.pages
        for index in pages.indices {
            pages[index].body.shiftSizes(by: new.fontSize - old.fontSize)
            if new.defaultAlignment != old.defaultAlignment {
                pages[index].body.setAllAlignments(new.defaultAlignment)
            }
        }
        report.pages = pages
        textRevision += 1
    }

    func rebuildSnapshot() {
        snapshot = DocumentSnapshot(report: report, images: images)
    }

    // MARK: - Text editing (called by the canvas)

    func pageTextChanged(_ id: UUID, _ text: NSAttributedString) {
        guard let index = report.pageIndex(of: id) else { return }
        report.pages[index].body = BodyStyler.document(from: text, settings: report.textStyle)
    }

    /// Inserts a ready phrase at the cursor, or at the end of the visible page when not writing.
    func insertPhrase(_ phrase: String) {
        if let textView = richText.textView, textView.window != nil, activePageID != nil {
            richText.insertText(phrase)
            return
        }
        let index = min(visiblePageIndex, pageCount - 1)
        let current = attributedText(ofPage: index)
        let text = NSMutableAttributedString(attributedString: current)
        let prefix = current.length == 0 || current.string.hasSuffix("\n") ? "" : "\n"
        text.append(NSAttributedString(string: prefix + phrase, attributes: typingAttributes))
        pageTextChanged(report.pages[index].id, text)
        textRevision += 1
    }

    func beganEditing(page id: UUID, textView: UITextView) {
        activePageID = id
        richText.attach(textView)
        if selection != nil { selection = nil }
    }

    // MARK: - Undo (pages, elements, formatting)

    private func recordUndo(_ title: String) {
        undoState = report
        undoTitle = title
    }

    func undo() {
        guard let saved = undoState else { return }
        undoState = nil
        undoTitle = nil
        selection = nil
        report = saved
        textRevision += 1
        rebuildSnapshot()
    }

    // MARK: - Pages

    /// Inserts an empty page after `index` (or at the end). Returns its id.
    @discardableResult
    func addPage(after index: Int? = nil) -> UUID {
        let page = ReportPage()
        let position = min((index ?? pageCount - 1) + 1, pageCount)
        report.pages.insert(page, at: position)
        visiblePageIndex = position
        rebuildSnapshot()
        return page.id
    }

    var canDeletePages: Bool { pageCount > 1 }

    func deletePage(at index: Int) {
        guard pageCount > 1, report.pages.indices.contains(index) else { return }
        recordUndo("حذف الصفحة")
        let removed = report.pages[index]
        report.pages.remove(at: index)
        if let signaturePage = report.signaturePageValue {
            report.signaturePageValue = signaturePage == index ? nil : (signaturePage > index ? signaturePage - 1 : signaturePage)
        }
        if activePageID == removed.id { activePageID = nil }
        if case .element(let id) = selection, removed.elements.contains(where: { $0.id == id }) { selection = nil }
        visiblePageIndex = min(index, pageCount - 1)
        textRevision += 1
        rebuildSnapshot()
    }

    func movePage(at index: Int, by offset: Int) {
        let target = index + offset
        guard report.pages.indices.contains(index), report.pages.indices.contains(target) else { return }
        report.pages.swapAt(index, target)
        if let signaturePage = report.signaturePageValue {
            if signaturePage == index { report.signaturePageValue = target } else if signaturePage == target { report.signaturePageValue = index }
        }
        visiblePageIndex = target
        textRevision += 1
        rebuildSnapshot()
    }

    /// Moves a page to any position (drag & drop in the preview).
    func movePage(from source: Int, to destination: Int) {
        guard report.pages.indices.contains(source), report.pages.indices.contains(destination), source != destination else { return }
        recordUndo("ترتيب الصفحات")
        var pages = report.pages
        let page = pages.remove(at: source)
        pages.insert(page, at: destination)
        let signatureID = report.signaturePageValue.flatMap { report.pages.indices.contains($0) ? report.pages[$0].id : nil }
        report.pages = pages
        if let signatureID { report.signaturePageValue = pages.firstIndex { $0.id == signatureID } }
        visiblePageIndex = destination
        textRevision += 1
        rebuildSnapshot()
    }

    /// Moves the text that does not fit on a page to a new page right after it.
    func moveOverflowToNewPage(_ index: Int) {
        rebuildSnapshot()
        guard snapshot.texts.indices.contains(index), let location = snapshot.texts[index].overflowLocation else { return }
        let text = attributedText(ofPage: index)
        guard location < text.length else { return }
        recordUndo("نقل النص الزائد")

        var keep = location
        let string = text.string as NSString
        // Break at the start of the overflowing line's word so no word is cut.
        while keep > 0, let scalar = UnicodeScalar(string.character(at: keep - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            keep -= 1
        }
        if keep == 0 { keep = location }

        let first = text.attributedSubstring(from: NSRange(location: 0, length: keep))
        var restStart = keep
        while restStart < string.length, let scalar = UnicodeScalar(string.character(at: restStart)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            restStart += 1
        }
        let rest = text.attributedSubstring(from: NSRange(location: restStart, length: string.length - restStart))

        report.pages[index].body = BodyStyler.document(from: first, settings: report.textStyle)
        var newPage = ReportPage()
        newPage.body = BodyStyler.document(from: rest, settings: report.textStyle)
        report.pages.insert(newPage, at: index + 1)
        if let signaturePage = report.signaturePageValue, signaturePage > index {
            report.signaturePageValue = signaturePage + 1
        }
        visiblePageIndex = index + 1
        textRevision += 1
        rebuildSnapshot()
    }

    // MARK: - Elements

    func element(_ id: UUID) -> PageElement? {
        guard let location = report.locate(element: id) else { return nil }
        return report.pages[location.page].elements[location.element]
    }

    func updateElement(_ id: UUID, _ change: (inout PageElement) -> Void) {
        guard let location = report.locate(element: id) else { return }
        var element = report.pages[location.page].elements[location.element]
        change(&element)
        report.pages[location.page].elements[location.element] = element
    }

    /// Adds an evidence box (or text box) to a page and selects it. Returns its id.
    @discardableResult
    func addElement(_ kind: PageElement.Kind, toPage index: Int) -> UUID {
        let page = min(max(index, 0), pageCount - 1)
        let rect = DocumentLayout.defaultRect(for: kind, report: report, spec: snapshot.spec, page: page)
        let element: PageElement
        switch kind {
        case .evidence: element = .evidence(rect: rect)
        case .text: element = .text(rect: rect)
        case .table: element = .table(rect: rect)
        }
        report.pages[page].elements.append(element)
        selection = .element(element.id)
        rebuildSnapshot()
        return element.id
    }

    func setElementRect(_ id: UUID, _ rect: CGRect) {
        updateElement(id) { element in
            element.rect = DocumentLayout.clamp(rect, minimum: element.minimumSize)
        }
    }

    /// Moves an element to another page (keeping its place unless a new rect is given).
    func moveElement(_ id: UUID, toPage target: Int, rect: CGRect? = nil) {
        guard let location = report.locate(element: id), report.pages.indices.contains(target) else { return }
        guard location.page != target else {
            if let rect { setElementRect(id, rect) }
            return
        }
        recordUndo("نقل العنصر")
        var pages = report.pages
        var element = pages[location.page].elements.remove(at: location.element)
        element.rect = DocumentLayout.clamp(rect ?? element.rect, minimum: element.minimumSize)
        pages[target].elements.append(element)
        report.pages = pages
        selection = .element(id)
        visiblePageIndex = target
        rebuildSnapshot()
    }

    func deleteElement(_ id: UUID) {
        guard report.locate(element: id) != nil else { return }
        recordUndo("حذف العنصر")
        for index in report.pages.indices {
            report.pages[index].elements.removeAll { $0.id == id }
        }
        if selection == .element(id) { selection = nil }
        rebuildSnapshot()
    }

    // Evidence content

    func addEvidencePhotos(_ sources: [Data], to id: UUID) async {
        isProcessingImage = true
        defer { isProcessingImage = false }
        var failed = 0
        for data in sources {
            guard element(id)?.evidence?.canAddItems == true else { break }
            do {
                let jpeg = try await ImageProcessor.photoJPEG(data)
                updateElement(id) { $0.evidence?.items.append(EvidenceItem(kind: .photo, imageData: jpeg)) }
            } catch {
                failed += 1
            }
        }
        if failed > 0 { errorMessage = "تعذر إضافة \(failed) من الصور." }
    }

    func addEvidenceQR(text: String, caption: String, to id: UUID) {
        let link = text.trimmed
        guard !link.isEmpty, element(id)?.evidence?.canAddItems == true else { return }
        guard QRMatrix.make(link) != nil else {
            errorMessage = "النص طويل جداً لرمز QR."
            return
        }
        updateElement(id) { $0.evidence?.items.append(EvidenceItem(kind: .qr, qrText: link, caption: caption.trimmed)) }
    }

    func removeEvidenceItem(_ itemID: UUID, from id: UUID) {
        updateElement(id) { $0.evidence?.items.removeAll { $0.id == itemID } }
    }

    func moveEvidenceItem(_ itemID: UUID, in id: UUID, by offset: Int) {
        updateElement(id) { element in
            guard var block = element.evidence, let index = block.items.firstIndex(where: { $0.id == itemID }) else { return }
            let target = index + offset
            guard block.items.indices.contains(target) else { return }
            block.items.swapAt(index, target)
            element.evidence = block
        }
    }

    // MARK: - Signatures block

    func setSignatureRect(_ rect: CGRect) {
        report.signatureRectValue = DocumentLayout.clamp(rect, minimum: CGSize(width: 120, height: 60))
        if report.signaturePageValue == nil, let current = snapshot.signature?.page, current != pageCount - 1 {
            report.signaturePageValue = current
        }
    }

    func moveSignatures(toPage index: Int) {
        report.signaturePageValue = index >= pageCount - 1 ? nil : index
        report.signatureRectValue = nil
        rebuildSnapshot()
    }

    func resetSignaturePosition() {
        report.signatureRectValue = nil
        report.signaturePageValue = nil
    }

    func addEmployee() {
        report.footer.employees.append(Employee())
        report.footer.showSignatureBlock = true
    }

    func removeEmployee(_ id: UUID) {
        report.footer.employees.removeAll { $0.id == id }
    }

    func setSignature(png: Data, for employeeID: UUID) {
        guard let index = report.footer.employees.firstIndex(where: { $0.id == employeeID }) else { return }
        report.footer.employees[index].signaturePNG = png
    }

    func removeSignature(for employeeID: UUID) {
        guard let index = report.footer.employees.firstIndex(where: { $0.id == employeeID }) else { return }
        report.footer.employees[index].signaturePNG = nil
    }

    func importSignature(_ data: Data, for employeeID: UUID) async {
        if let processed = await processImage(data, mode: .smart) {
            setSignature(png: processed, for: employeeID)
        }
    }

    func importStamp(_ data: Data) async {
        if let processed = await processImage(data, mode: .smart) {
            report.footer.stampPNG = processed
        }
    }

    // MARK: - Logo

    func importLogo(_ data: Data) async {
        originalLogoData = data
        await processLogo()
    }

    func reprocessLogo() async {
        await processLogo()
    }

    private func processLogo() async {
        guard let source = originalLogoData ?? report.header.logoPNG else { return }
        if let processed = await processImage(source, mode: logoRemovalMode) {
            report.header.logoPNG = processed
        }
    }

    func removeLogo() {
        originalLogoData = nil
        report.header.logoPNG = nil
        if selection == .logo { selection = nil }
    }

    /// Logo box on a page in A4 points (nil when that page has no letterhead or there is no logo).
    func logoBox(onPage index: Int) -> CGRect? {
        let spec = snapshot.spec
        guard report.header.logoPNG != nil, spec.hasHeader(bodyPage: index) else { return nil }
        return PageRenderer.logoBox(header: report.header, headerRect: spec.headerRect(bodyPage: index))
    }

    /// Applies a logo frame chosen on the canvas (size from its width, position as an offset).
    func setLogoFrame(_ rect: CGRect, onPage index: Int) {
        let spec = snapshot.spec
        guard spec.hasHeader(bodyPage: index) else { return }
        let scale = Double(rect.width / PageRenderer.defaultLogoSide)
        var header = report.header
        header.logoScale = min(max(scale, HeaderInfo.logoScaleRange.lowerBound), HeaderInfo.logoScaleRange.upperBound)
        header.logoOffset = .zero
        let automatic = PageRenderer.logoBox(header: header, headerRect: spec.headerRect(bodyPage: index))
        header.logoOffset = CGSize(width: rect.minX - automatic.minX, height: rect.minY - automatic.minY)
        report.header = header
    }

    func resetLogoPosition() {
        report.header.logoOffset = .zero
        report.header.logoScale = 1
    }

    // MARK: - Organisation letterhead & frame images

    func importLetterhead(_ data: Data, top: Bool) async {
        guard let processed = await processImage(data, mode: .smart, maxPixelSize: 2400, trim: true),
              let image = UIImage(data: processed), image.size.width > 0 else { return }
        let aspect = Double(image.size.height / image.size.width)
        if top {
            report.frame.letterheadTopPNG = processed
            report.frame.letterheadTopAspect = aspect
        } else {
            report.frame.letterheadBottomPNG = processed
            report.frame.letterheadBottomAspect = aspect
        }
        if report.frame.style != .none && report.frame.style != .customImage {
            report.frame.style = .none
        }
    }

    func removeLetterhead(top: Bool) {
        if top {
            report.frame.letterheadTopPNG = nil
            report.frame.letterheadTopAspect = nil
        } else {
            report.frame.letterheadBottomPNG = nil
            report.frame.letterheadBottomAspect = nil
        }
    }

    func importFrameImage(_ data: Data) async {
        if let processed = await processImage(data, mode: .allWhite, maxPixelSize: 2400, trim: false) {
            report.frame.customFramePNG = processed
            report.frame.style = .customImage
        }
    }

    func removeFrameImage() {
        report.frame.customFramePNG = nil
        if report.frame.style == .customImage { report.frame.style = .double }
    }

    private func processImage(_ data: Data, mode: LogoBackgroundMode, maxPixelSize: Int = 1000, trim: Bool = true) async -> Data? {
        isProcessingImage = true
        defer { isProcessingImage = false }
        do {
            return try await ImageProcessor.process(data, mode: mode, maxPixelSize: maxPixelSize, trim: trim)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Formatting & proofreading (all pages)

    /// Local spacing / punctuation clean-up on every page. Returns the number of edits.
    @discardableResult
    func formatAllText(recordingUndo: Bool = true) -> Int {
        var pages = report.pages
        var edits = 0
        for index in pages.indices {
            let text = NSMutableAttributedString(attributedString: attributedText(ofPage: index))
            let count = ArabicTextFormatter.format(text)
            guard count > 0 else { continue }
            BodyStyler.normalizeParagraphStyles(text, settings: report.textStyle)
            pages[index].body = BodyStyler.document(from: text, settings: report.textStyle)
            edits += count
        }
        guard edits > 0 else { return 0 }
        if recordingUndo { recordUndo("تنسيق النص") }
        report.pages = pages
        textRevision += 1
        return edits
    }

    func autoFormatIfEnabled() {
        guard report.autoFormat else { return }
        formatAllText(recordingUndo: false)
    }

    /// AI spelling & grammar correction of every page, word by word. Returns corrected words.
    func proofreadWithAI(progress: @escaping (Int, Int) -> Void) async throws -> Int {
        let context = AIReportContext(
            title: report.title,
            ministry: report.header.ministry,
            administration: report.header.generalAdministration,
            department: report.header.department
        )
        var pages = report.pages
        var total = 0
        for index in pages.indices where !pages[index].body.isEmpty {
            progress(index + 1, pages.count)
            let (corrected, changes) = try await ProofreadService().proofread(attributedText(ofPage: index), context: context) { _, _ in }
            guard changes > 0 else { continue }
            let text = NSMutableAttributedString(attributedString: corrected)
            BodyStyler.normalizeParagraphStyles(text, settings: report.textStyle)
            pages[index].body = BodyStyler.document(from: text, settings: report.textStyle)
            total += changes
        }
        guard total > 0 else { return 0 }
        recordUndo("التدقيق الإملائي")
        report.pages = pages
        textRevision += 1
        return total
    }

    // MARK: - Form fields

    func addFormField() {
        report.form.fields.append(FormField(label: "حقل جديد", width: .half))
    }

    func removeFormField(_ id: UUID) {
        report.form.fields.removeAll { $0.id == id }
    }

    func moveFormField(_ id: UUID, by offset: Int) {
        guard let index = report.form.fields.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard report.form.fields.indices.contains(target) else { return }
        report.form.fields.swapAt(index, target)
    }

    func applyFormTemplate(_ template: FormTemplate) {
        report.form.fields = template.makeFields(hijriYear: ArabicFormat.hijri(Date(), report.page.numerals))
        if template.id != FormTemplate.blank.id {
            report.title = template.title
        }
    }

    // MARK: - Header templates

    func makeTemplate(named name: String) -> HeaderTemplate {
        let trimmed = name.trimmed
        let fallback = report.header.ministry.trimmed.isEmpty ? "قالب" : report.header.ministry.trimmed
        return HeaderTemplate(name: trimmed.isEmpty ? fallback : trimmed, header: report.header, frame: report.frame)
    }

    func applyTemplate(_ template: HeaderTemplate) {
        var header = template.header
        header.date = report.header.date
        header.referenceNumber = report.header.referenceNumber
        header.attachments = report.header.attachments
        originalLogoData = nil
        report.header = header
        report.frame = template.frame
    }

    // MARK: - Persistence & export

    func saveNow() {
        guard hasUnsavedChanges else { return }
        var copy = report
        copy.updatedAt = Date()
        store.saveInBackground(copy)
        hasUnsavedChanges = false
    }

    /// One JPG per page (for WhatsApp and similar).
    func exportImages() -> [URL] {
        selection = nil
        autoFormatIfEnabled()
        rebuildSnapshot()
        saveNow()
        do {
            return try ImageExporter.export(snapshot)
        } catch {
            errorMessage = "تعذر إنشاء الصور: \(error.localizedDescription)"
            return []
        }
    }

    func exportPDF() -> URL? {
        selection = nil
        autoFormatIfEnabled()
        rebuildSnapshot()
        saveNow()
        do {
            return try PDFExporter.export(snapshot)
        } catch {
            errorMessage = "تعذر إنشاء ملف PDF: \(error.localizedDescription)"
            return nil
        }
    }
}
