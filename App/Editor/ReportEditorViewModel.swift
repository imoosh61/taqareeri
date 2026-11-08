import Combine
import Foundation
import UIKit

struct BodySection: Identifiable, Equatable {
    let id: Int
    let range: NSRange
    let preview: String
}

/// Owns one report while it is being edited: live pagination, autosave, images, export.
@MainActor
final class ReportEditorViewModel: ObservableObject {
    @Published var report: Report
    @Published private(set) var pagination: PaginationResult
    @Published private(set) var images: RenderImages
    @Published private(set) var cursorBodyPage = 0
    /// Bumped whenever the body text is replaced from outside the text view.
    @Published private(set) var bodyRevision = 0
    @Published var logoRemovalMode: LogoBackgroundMode = .smart
    @Published private(set) var isProcessingImage = false
    @Published var errorMessage: String?

    let richText = RichTextController()
    private(set) var bodyText: NSAttributedString

    private let store: ReportStore
    private var appliedTextStyle: TextStyleSettings
    private var originalLogoData: Data?
    private var cursorLocation = 0
    private var hasUnsavedChanges = false
    private let bodyChanged = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(report: Report, store: ReportStore) {
        self.report = report
        self.store = store
        self.appliedTextStyle = report.textStyle
        let text = BodyStyler.attributedString(from: report.body, settings: report.textStyle)
        self.bodyText = text
        self.images = RenderImages(report: report)
        self.pagination = Paginator.paginate(text, spec: PageLayoutSpec(report: report), hasCover: report.cover.isEnabled)
        configureRichText()
        bindPipelines()
    }

    // MARK: - Derived

    var renderContext: PageRenderContext {
        PageRenderContext(report: report, pagination: pagination, images: images)
    }

    var cursorPhysicalPage: Int { pagination.physicalPage(forBodyPage: cursorBodyPage) }
    var firstBodyPhysicalPage: Int { pagination.firstBodyPhysicalPage }

    var typingAttributes: [NSAttributedString.Key: Any] {
        BodyStyler.typingAttributes(report.textStyle)
    }

    func pageLabel(forPhysicalPage page: Int) -> String {
        ArabicFormat.pageLabel(page + 1, of: pagination.totalPages, report.page.numerals)
    }

    // MARK: - Wiring

    private func configureRichText() {
        richText.settingsProvider = { [weak self] in self?.report.textStyle ?? TextStyleSettings() }
        richText.onTextChanged = { [weak self] text in self?.bodyDidChange(text) }
        richText.onSelectionChanged = { [weak self] location in self?.selectionDidChange(location) }
    }

    private func bindPipelines() {
        // `$report` emits the new value *before* `report` is updated.
        $report
            .dropFirst()
            .sink { [weak self] newValue in self?.reportWillChange(to: newValue) }
            .store(in: &cancellables)

        // Re-paginate only when something that moves text changed (not frame style/colour, logo, etc.).
        let layoutChange = $report
            .map(LayoutKey.init)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        Publishers.Merge(layoutChange, bodyChanged)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.repaginate() }
            .store(in: &cancellables)

        let anyChange = Publishers.Merge($report.dropFirst().map { _ in () }, bodyChanged)

        anyChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &cancellables)
    }

    private func reportWillChange(to newValue: Report) {
        hasUnsavedChanges = true

        if newValue.textStyle != appliedTextStyle {
            bodyText = BodyStyler.restyle(bodyText, from: appliedTextStyle, to: newValue.textStyle)
            appliedTextStyle = newValue.textStyle
            bodyRevision += 1
        }

        if RenderImages.sources(of: newValue) != RenderImages.sources(of: report) {
            images = RenderImages(report: newValue)
        }
    }

    private func bodyDidChange(_ text: NSAttributedString) {
        bodyText = text
        hasUnsavedChanges = true
        bodyChanged.send()
    }

    private func selectionDidChange(_ location: Int) {
        cursorLocation = location
        updateCursorPage()
    }

    private func updateCursorPage() {
        let page = min(pagination.bodyPage(forCharacterAt: cursorLocation), pagination.lastBodyPage)
        if page != cursorBodyPage { cursorBodyPage = page }
    }

    func repaginate() {
        pagination = Paginator.paginate(bodyText, spec: PageLayoutSpec(report: report), hasCover: report.cover.isEnabled)
        updateCursorPage()
    }

    // MARK: - Persistence

    func saveNow() {
        guard hasUnsavedChanges else { return }
        var snapshot = report
        snapshot.body = BodyStyler.document(from: bodyText, settings: report.textStyle)
        snapshot.updatedAt = Date()
        store.saveInBackground(snapshot)
        hasUnsavedChanges = false
    }

    // MARK: - Images

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
    }

    // MARK: - Employees

    func addEmployee() {
        report.footer.employees.append(Employee())
        report.footer.showSignatureBlock = true
    }

    func removeEmployee(_ id: UUID) {
        report.footer.employees.removeAll { $0.id == id }
    }

    func moveEmployees(from source: IndexSet, to destination: Int) {
        report.footer.employees.move(fromOffsets: source, toOffset: destination)
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

    // MARK: - Formatting & proofreading

    @Published private(set) var canUndoTextChange = false
    private var undoSnapshot: NSAttributedString?

    private func replaceBody(_ text: NSAttributedString, keepUndo: Bool) {
        if keepUndo {
            undoSnapshot = bodyText
            canUndoTextChange = true
        }
        bodyText = text
        bodyRevision += 1
        hasUnsavedChanges = true
        bodyChanged.send()
    }

    /// Local spacing / punctuation clean-up. Returns the number of edits.
    @discardableResult
    func formatText(keepUndo: Bool = true) -> Int {
        let text = NSMutableAttributedString(attributedString: bodyText)
        let edits = ArabicTextFormatter.format(text)
        guard edits > 0 else { return 0 }
        BodyStyler.normalizeParagraphStyles(text, settings: report.textStyle)
        replaceBody(text, keepUndo: keepUndo)
        return edits
    }

    func autoFormatIfEnabled() {
        guard report.autoFormat else { return }
        formatText(keepUndo: false)
    }

    /// AI spelling & grammar correction applied word by word. Returns the number of corrected words.
    func proofreadWithAI(progress: @escaping (Int, Int) -> Void) async throws -> Int {
        let context = AIReportContext(
            title: report.title,
            ministry: report.header.ministry,
            administration: report.header.generalAdministration,
            department: report.header.department
        )
        let (corrected, changes) = try await ProofreadService().proofread(bodyText, context: context, progress: progress)
        guard changes > 0 else { return 0 }
        let text = NSMutableAttributedString(attributedString: corrected)
        BodyStyler.normalizeParagraphStyles(text, settings: report.textStyle)
        replaceBody(text, keepUndo: true)
        return changes
    }

    func undoTextChange() {
        guard let snapshot = undoSnapshot else { return }
        undoSnapshot = nil
        canUndoTextChange = false
        replaceBody(snapshot, keepUndo: false)
    }

    // MARK: - Free signature placement

    var lastBodyPhysicalPage: Int { pagination.physicalPage(forBodyPage: pagination.lastBodyPage) }

    func signatureLayout() -> PageRenderer.SignatureLayout {
        PageRenderer.signatureLayout(report: report, spec: pagination.spec,
                                     lastBodyPage: pagination.lastBodyPage, hasStamp: images.stamp != nil)
    }

    /// Moves an employee cell or the stamp by `delta` A4 points, keeping it on the page.
    func moveSignatureElement(_ element: SignatureElement, by delta: CGSize) {
        guard delta != .zero else { return }
        var automatic = report
        automatic.footer.resetPositions()
        let base = PageRenderer.signatureLayout(report: automatic, spec: pagination.spec,
                                                lastBodyPage: pagination.lastBodyPage, hasStamp: images.stamp != nil)
        let current = signatureLayout()
        let page = CGRect(origin: .zero, size: pagination.spec.pageSize)

        switch element {
        case .employee(let id):
            guard let index = report.footer.employees.firstIndex(where: { $0.id == id }),
                  let now = current.employees.first(where: { $0.id == id })?.rect,
                  let origin = base.employees.first(where: { $0.id == id })?.rect else { return }
            let target = PageRenderer.clamp(now.offsetBy(dx: delta.width, dy: delta.height), to: page)
            report.footer.employees[index].offset = CGSize(width: target.minX - origin.minX, height: target.minY - origin.minY)
        case .stamp:
            guard let now = current.stamp, let origin = base.stamp else { return }
            let target = PageRenderer.clamp(now.offsetBy(dx: delta.width, dy: delta.height), to: page)
            report.footer.stampOffset = CGSize(width: target.minX - origin.minX, height: target.minY - origin.minY)
        }
    }

    func resetSignaturePositions() {
        report.footer.resetPositions()
    }

    // MARK: - Custom frame

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

    func importStamp(_ data: Data) async {
        if let processed = await processImage(data, mode: .smart) {
            report.footer.stampPNG = processed
        }
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

    // MARK: - Templates

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

    // MARK: - Sections (content between page breaks)

    func sections() -> [BodySection] {
        let text = bodyText.string as NSString
        var result: [BodySection] = []
        var start = 0

        func section(_ id: Int, _ range: NSRange) -> BodySection {
            let preview = text.substring(with: range)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmed
            return BodySection(id: id, range: range, preview: String(preview.prefix(120)))
        }

        for index in 0..<text.length where text.character(at: index) == BodyDocument.pageBreakUnit {
            let item = section(result.count, NSRange(location: start, length: index - start))
            result.append(item)
            start = index + 1
        }
        let last = section(result.count, NSRange(location: start, length: text.length - start))
        result.append(last)
        return result
    }

    func reorderSections(_ order: [Int]) {
        let current = sections()
        guard order.count == current.count, Set(order) == Set(current.indices), order != Array(current.indices) else { return }

        let output = NSMutableAttributedString()
        for (position, index) in order.enumerated() {
            if position > 0 {
                output.append(NSAttributedString(string: BodyDocument.pageBreak, attributes: typingAttributes))
            }
            output.append(bodyText.attributedSubstring(from: current[index].range))
        }
        bodyText = output
        bodyRevision += 1
        hasUnsavedChanges = true
        bodyChanged.send()
    }

    // MARK: - Export

    func exportPDF() -> URL? {
        autoFormatIfEnabled()
        repaginate()
        saveNow()
        do {
            return try PDFExporter.export(renderContext)
        } catch {
            errorMessage = "تعذر إنشاء ملف PDF: \(error.localizedDescription)"
            return nil
        }
    }
}

enum SignatureElement: Hashable {
    case employee(UUID)
    case stamp
}

/// The parts of a report that affect where text falls on the pages.
private struct LayoutKey: Equatable {
    let textStyle: TextStyleSettings
    let page: PageSettings
    let headerEnabled: Bool
    let headerPlacement: HeaderPlacement
    let frameIsNone: Bool
    let coverEnabled: Bool
    let addressee: AddresseeSettings
    let addresseeFontSize: Double
    let signatureBlock: Bool
    let employeeCount: Int
    let hasStamp: Bool

    init(_ report: Report) {
        textStyle = report.textStyle
        page = report.page
        headerEnabled = report.header.isEnabled
        headerPlacement = report.header.placement
        frameIsNone = report.frame.style == .none
        coverEnabled = report.cover.isEnabled
        addressee = report.addressee
        addresseeFontSize = report.addresseeFontSize
        signatureBlock = report.footer.showSignatureBlock
        employeeCount = report.footer.employees.count
        hasStamp = report.footer.stampPNG != nil
    }
}
