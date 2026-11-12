import SwiftUI

/// The editor: the report's pages (write directly on them, drag elements on them) and one simple
/// bottom bar. Everything else opens as a sheet.
struct ReportEditorView: View {
    @StateObject private var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("spellcheck.live") private var liveSpellCheck = true

    @State private var sheet: EditorSheet?
    @State private var shareItem: IdentifiedURL?
    @State private var scrollRequest = 0
    @State private var pendingPageDeletion = false

    enum EditorSheet: Identifiable {
        case letterhead, format, signatures, fields, preview, ai, dictation
        case element(UUID)

        var id: String {
            switch self {
            case .element(let id): return "element-\(id)"
            default: return String(describing: self)
            }
        }
    }

    init(report: Report, store: ReportStore) {
        _vm = StateObject(wrappedValue: ReportEditorViewModel(report: report, store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                DocumentCanvas(
                    vm: vm,
                    tint: theme.accentUIColor,
                    spellCheck: liveSpellCheck,
                    onAI: { sheet = .ai },
                    onFormat: { sheet = .format },
                    onEdit: edit,
                    scrollRequest: scrollRequest
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)

                pageCapsule
                    .padding(.top, 8)
            }
            .overlay(alignment: .bottom) { overflowBanner }

            Divider()
            if let selection = vm.selection {
                selectionBar(selection)
            } else {
                mainBar
            }
        }
        .background(Color(.systemGray5))
        .navigationTitle(vm.report.title.trimmed.isEmpty ? "تقرير" : vm.report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let title = vm.undoTitle {
                    Button {
                        vm.undo()
                    } label: {
                        Label("تراجع عن \(title)", systemImage: "arrow.uturn.backward")
                    }
                }
                Button { sheet = .ai } label: { Label("الذكاء الاصطناعي", systemImage: "sparkles") }
                Button {
                    KeyboardHelper.dismiss()
                    sheet = .preview
                } label: {
                    Label("معاينة وتصدير", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sheet) { item in sheetContent(item) }
        .sheet(item: $shareItem, onDismiss: TempFiles.cleanup) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog("حذف الصفحة \(ArabicFormat.number(vm.visiblePageIndex + 1, vm.report.page.numerals))؟",
                            isPresented: $pendingPageDeletion, titleVisibility: .visible) {
            Button("حذف الصفحة", role: .destructive) { vm.deletePage(at: vm.visiblePageIndex) }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يُحذف نصها وشواهدها ومربعاتها. يمكنك التراجع بعدها.")
        }
        .alert("تنبيه", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("ملاحظة", isPresented: Binding(get: { vm.notice != nil }, set: { if !$0 { vm.notice = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(vm.notice ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.saveNow() }
        }
        .onDisappear { vm.saveNow() }
    }

    // MARK: - Page indicator & actions

    private var pageCapsule: some View {
        let index = min(vm.visiblePageIndex, vm.pageCount - 1)
        return Menu {
            Button { addPage(after: index) } label: { Label("صفحة جديدة بعد هذه", systemImage: "plus.rectangle.portrait") }
            Button { vm.addElement(.evidence, toPage: index); openSelected() } label: { Label("شواهد في هذه الصفحة", systemImage: "photo.on.rectangle") }
            Button { vm.addElement(.text, toPage: index); openSelected() } label: { Label("مربع نص في هذه الصفحة", systemImage: "character.textbox") }
            if vm.report.showsSignatures {
                Button { vm.moveSignatures(toPage: index) } label: { Label("نقل التوقيعات إلى هذه الصفحة", systemImage: "signature") }
            }
            Divider()
            Button { vm.movePage(at: index, by: -1); scrollRequest += 1 } label: { Label("تقديم الصفحة", systemImage: "arrow.up") }
                .disabled(index == 0)
            Button { vm.movePage(at: index, by: 1); scrollRequest += 1 } label: { Label("تأخير الصفحة", systemImage: "arrow.down") }
                .disabled(index >= vm.pageCount - 1)
            Button(role: .destructive) { pendingPageDeletion = true } label: { Label("حذف الصفحة", systemImage: "trash") }
                .disabled(!vm.canDeletePages)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text("صفحة \(ArabicFormat.number(index + 1, vm.report.page.numerals)) من \(ArabicFormat.number(vm.pageCount, vm.report.page.numerals))")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private var overflowBanner: some View {
        let index = min(vm.visiblePageIndex, vm.pageCount - 1)
        if vm.snapshot.texts.indices.contains(index), vm.snapshot.texts[index].overflowLocation != nil {
            Button {
                vm.moveOverflowToNewPage(index)
                scrollRequest += 1
            } label: {
                Label("النص أطول من هذه الصفحة — نقل الزائد لصفحة جديدة", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Bars

    private var mainBar: some View {
        HStack(spacing: 0) {
            Menu {
                Button { addPage(after: vm.visiblePageIndex) } label: { Label("صفحة جديدة", systemImage: "plus.rectangle.portrait") }
                Button { vm.addElement(.evidence, toPage: vm.visiblePageIndex); openSelected() } label: { Label("شواهد (صور / QR)", systemImage: "photo.on.rectangle") }
                Button { vm.addElement(.text, toPage: vm.visiblePageIndex); openSelected() } label: { Label("مربع نص", systemImage: "character.textbox") }
                Button { sheet = .dictation } label: { Label("إملاء صوتي", systemImage: "mic") }
            } label: {
                barItem("إضافة", "plus.circle.fill", prominent: true)
            }
            if vm.report.kind == .form {
                Button { sheet = .fields } label: { barItem("الحقول", "list.bullet.rectangle") }
            }
            Button { sheet = .letterhead } label: { barItem("الترويسة", "rectangle.topthird.inset.filled") }
            Button { sheet = .format } label: { barItem("تنسيق", "textformat") }
            Button { sheet = .signatures } label: { barItem("التوقيع", "signature") }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
    }

    private func selectionBar(_ selection: ReportEditorViewModel.Selection) -> some View {
        HStack(spacing: 0) {
            switch selection {
            case .element(let id):
                Button { sheet = .element(id) } label: { barItem(vm.element(id)?.kind == .text ? "تعديل النص" : "الصور", "pencil", prominent: true) }
                Button { vm.deleteElement(id) } label: { barItem("حذف", "trash") }
            case .signatures:
                Button { sheet = .signatures } label: { barItem("الأسماء", "person.2", prominent: true) }
                Button { vm.resetSignaturePosition() } label: { barItem("الموضع التلقائي", "arrow.counterclockwise") }
            case .logo:
                Button { sheet = .letterhead } label: { barItem("الشعار", "seal", prominent: true) }
                Button { vm.resetLogoPosition() } label: { barItem("الأصل", "arrow.counterclockwise") }
            }
            Button { vm.selection = nil } label: { barItem("تم", "checkmark.circle") }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Text("اسحب العنصر لتحريكه، واسحب الدائرة في زاويته لتغيير حجمه")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .offset(y: -34)
        }
    }

    private func barItem(_ title: String, _ icon: String, prominent: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 24 : 20, weight: .semibold))
                .foregroundStyle(prominent ? theme.accent : Color.primary)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func addPage(after index: Int) {
        vm.addPage(after: index)
        scrollRequest += 1
    }

    private func openSelected() {
        if case .element(let id) = vm.selection, vm.element(id)?.kind == .evidence {
            sheet = .element(id)
        }
    }

    private func edit(_ selection: ReportEditorViewModel.Selection) {
        switch selection {
        case .element(let id): sheet = .element(id)
        case .signatures: sheet = .signatures
        case .logo: sheet = .letterhead
        }
    }

    private func export() {
        KeyboardHelper.dismiss()
        if let url = vm.exportPDF() {
            shareItem = IdentifiedURL(url: url)
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: EditorSheet) -> some View {
        switch item {
        case .letterhead: LetterheadSheet(vm: vm)
        case .format: FormatSheet(vm: vm).presentationDetents([.medium, .large])
        case .signatures: SignaturesSheet(vm: vm)
        case .fields: FormFieldsSheet(vm: vm)
        case .preview: PreviewSheet(vm: vm) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { export() } }
        case .ai: AIAssistantSheet(vm: vm)
        case .dictation:
            DictationSheet { text in vm.richText.insertText(text) }
                .presentationDetents([.medium, .large])
        case .element(let id): ElementSheet(vm: vm, elementID: id).presentationDetents([.medium, .large])
        }
    }
}
