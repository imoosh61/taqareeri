import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// Edits the content of an element placed on a page (evidence box or text box).
/// Position and size are changed directly on the page.
struct ElementSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    let elementID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showQR = false
    @State private var qrLink = ""
    @State private var qrCaption = ""
    @State private var showScanner = false

    private var element: PageElement? { vm.element(elementID) }

    var body: some View {
        NavigationStack {
            Group {
                if let element {
                    Form {
                        switch element.kind {
                        case .evidence: evidenceSections(element.evidence ?? EvidenceBlock())
                        case .text: textSections()
                        case .table: tableSections(element.table ?? TableBlock())
                        }
                        Section {
                            Button(role: .destructive) {
                                vm.deleteElement(elementID)
                                dismiss()
                            } label: {
                                Label("حذف \(element.title)", systemImage: "trash")
                            }
                        } footer: {
                            Text("لتحريكه أو تغيير حجمه: اضغط عليه في الصفحة ثم اسحبه أو اسحب زاويته.")
                        }
                    }
                } else {
                    ContentUnavailableView("العنصر غير موجود", systemImage: "questionmark.square.dashed")
                }
            }
            .navigationTitle(element?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                    }
                    await vm.addEvidencePhotos(datas, to: elementID)
                    photoItems = []
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { images in
                    showScanner = false
                    let datas = images.compactMap { $0.jpegData(compressionQuality: 0.85) }
                    guard !datas.isEmpty else { return }
                    Task { await vm.addEvidencePhotos(datas, to: elementID) }
                }
                .ignoresSafeArea()
            }
            .alert("إضافة رمز QR", isPresented: $showQR) {
                TextField("الرابط أو النص", text: $qrLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("تعليق تحت الرمز (اختياري)", text: $qrCaption)
                Button("إضافة") {
                    vm.addEvidenceQR(text: qrLink, caption: qrCaption, to: elementID)
                    qrLink = ""
                    qrCaption = ""
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("يُنشأ الرمز تلقائياً، ويمسحه أي شخص بكاميرا الجوال ليفتح الرابط.")
            }
        }
    }

    // MARK: - Evidence

    @ViewBuilder
    private func evidenceSections(_ block: EvidenceBlock) -> some View {
        Section {
            ForEach(Array(block.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    thumbnail(item).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kind == .photo ? "صورة \(ArabicFormat.number(index + 1, vm.report.page.numerals))" : "رمز QR")
                            .font(.subheadline.weight(.semibold))
                        TextField("تعليق تحت العنصر", text: captionBinding(item.id))
                            .font(.subheadline)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("تقديم") { vm.moveEvidenceItem(item.id, in: elementID, by: -1) }
                            .disabled(index == 0)
                        Button("تأخير") { vm.moveEvidenceItem(item.id, in: elementID, by: 1) }
                            .disabled(index == block.items.count - 1)
                        Button("حذف", role: .destructive) { vm.removeEvidenceItem(item.id, from: elementID) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
            }
            if block.canAddItems {
                PhotosPicker(selection: $photoItems, maxSelectionCount: EvidenceBlock.maxItems - block.items.count, matching: .images) {
                    Label("إضافة صور", systemImage: "photo.on.rectangle.angled")
                }
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showScanner = true
                    } label: {
                        Label("مسح مستند بالكاميرا", systemImage: "doc.viewfinder")
                    }
                }
                Button {
                    showQR = true
                } label: {
                    Label("إضافة رمز QR من رابط", systemImage: "qrcode")
                }
            }
            if vm.isProcessingImage {
                HStack { ProgressView(); Text("جارٍ تجهيز الصور…").foregroundStyle(.secondary) }
            }
        } header: {
            Text("العناصر (\(ArabicFormat.number(block.items.count, vm.report.page.numerals)) من \(ArabicFormat.number(EvidenceBlock.maxItems, vm.report.page.numerals)))")
        } footer: {
            if block.items.isEmpty {
                Text("مربع الشواهد الفارغ لا يظهر في التقرير المصدَّر.")
            }
        }

        Section("الشكل") {
            TextField("عنوان المربع (مثل: الشواهد)", text: evidenceBinding(\.title))
            Toggle("إطار حول الشواهد", isOn: evidenceBinding(\.showBorder))
            Toggle("ملء المربعات بالصور (قص الأطراف)", isOn: evidenceBinding(\.fillCells))
        }
    }

    // MARK: - Text box

    @ViewBuilder
    private func textSections() -> some View {
        Section("النص") {
            TextField("اكتب النص", text: textBinding(\.text), axis: .vertical)
                .lineLimit(1...8)
        }
        Section("الشكل") {
            FontSizeSlider(title: "حجم الخط", value: textBinding(\.fontSize), defaultValue: 14,
                           numerals: vm.report.page.numerals, range: 8...40)
            Toggle("عريض", isOn: textBinding(\.bold))
            Toggle("إطار حول المربع", isOn: textBinding(\.showBorder))
            Picker("المحاذاة", selection: textBinding(\.alignment)) {
                ForEach([ParagraphAlignment.left, .center, .right]) { Image(systemName: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .environment(\.layoutDirection, .leftToRight)
            ColorPicker("لون النص", selection: Binding(
                get: { Color(hex: element?.text?.colorHex ?? "000000") },
                set: { color in vm.updateElement(elementID) { $0.text?.colorHex = UIColor(color).hexString } }
            ), supportsOpacity: false)
        }
    }

    // MARK: - Table

    @ViewBuilder
    private func tableSections(_ table: TableBlock) -> some View {
        Section {
            Stepper(value: Binding(
                get: { table.columnCount },
                set: { count in
                    vm.updateElement(elementID) { element in
                        guard var block = element.table else { return }
                        while block.columnCount < count && block.columnCount < TableBlock.maxColumns { block.addColumn() }
                        while block.columnCount > count && block.columnCount > 1 { block.removeColumn(at: block.columnCount - 1) }
                        element.table = block
                    }
                }
            ), in: 1...TableBlock.maxColumns) {
                LabeledValue(title: "عدد الأعمدة", value: ArabicFormat.number(table.columnCount, vm.report.page.numerals))
            }
            Toggle("الصف الأول عناوين (ملوّن)", isOn: tableBinding(\.hasHeaderRow))
            FontSizeSlider(title: "حجم الخط", value: tableBinding(\.fontSize), defaultValue: 12,
                           numerals: vm.report.page.numerals, range: 8...20)
            ColorPicker("لون الجدول", selection: Binding(
                get: { Color(hex: table.colorHex) },
                set: { color in vm.updateElement(elementID) { $0.table?.colorHex = UIColor(color).hexString } }
            ), supportsOpacity: false)
            Button {
                vm.updateElement(elementID) { element in
                    guard let block = element.table else { return }
                    var rect = element.rect
                    rect.size.height = block.preferredHeight
                    element.rect = DocumentLayout.clamp(rect, minimum: element.minimumSize)
                }
            } label: {
                Label("ضبط ارتفاع الجدول على عدد الصفوف", systemImage: "arrow.up.and.down.text.horizontal")
            }
        } header: {
            Text("الجدول")
        }

        ForEach(Array(table.rows.indices), id: \.self) { row in
            Section {
                ForEach(0..<table.columnCount, id: \.self) { column in
                    TextField(columnPlaceholder(table, row: row, column: column), text: cellBinding(row: row, column: column), axis: .vertical)
                        .lineLimit(1...3)
                }
            } header: {
                HStack {
                    Text(row == 0 && table.hasHeaderRow ? "العناوين" : "الصف \(ArabicFormat.number(table.hasHeaderRow ? row : row + 1, vm.report.page.numerals))")
                    Spacer()
                    if table.rowCount > 1 {
                        Button(role: .destructive) {
                            vm.updateElement(elementID) { $0.table?.removeRow(at: row) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("حذف الصف")
                    }
                }
            }
        }

        if table.rowCount < TableBlock.maxRows {
            Section {
                Button {
                    vm.updateElement(elementID) { element in
                        guard var block = element.table else { return }
                        block.addRow()
                        // Number the new row automatically when the first column is a counter.
                        let last = block.rowCount - 1
                        if block.hasHeaderRow, block.rows[0].first?.trimmed == "م" {
                            block.rows[last][0] = ArabicFormat.number(last, vm.report.page.numerals)
                        }
                        element.table = block
                        var rect = element.rect
                        rect.size.height += CGFloat(block.fontSize) * 2.1
                        element.rect = DocumentLayout.clamp(rect, minimum: element.minimumSize)
                    }
                } label: {
                    Label("إضافة صف", systemImage: "plus.rectangle")
                }
            }
        }
    }

    private func columnPlaceholder(_ table: TableBlock, row: Int, column: Int) -> String {
        if row > 0, table.hasHeaderRow {
            let header = table.rows[0][column].trimmed
            if !header.isEmpty { return header }
        }
        return "العمود \(ArabicFormat.number(column + 1, vm.report.page.numerals))"
    }

    private func tableBinding<Value>(_ keyPath: WritableKeyPath<TableBlock, Value>) -> Binding<Value> {
        Binding(
            get: { (vm.element(elementID)?.table ?? TableBlock())[keyPath: keyPath] },
            set: { value in vm.updateElement(elementID) { $0.table?[keyPath: keyPath] = value } }
        )
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard let table = vm.element(elementID)?.table, table.rows.indices.contains(row),
                      table.rows[row].indices.contains(column) else { return "" }
                return table.rows[row][column]
            },
            set: { value in
                vm.updateElement(elementID) { element in
                    guard let table = element.table, table.rows.indices.contains(row),
                          table.rows[row].indices.contains(column) else { return }
                    element.table?.rows[row][column] = value
                }
            }
        )
    }

    // MARK: - Bindings

    private func evidenceBinding<Value>(_ keyPath: WritableKeyPath<EvidenceBlock, Value>) -> Binding<Value> {
        Binding(
            get: { (vm.element(elementID)?.evidence ?? EvidenceBlock())[keyPath: keyPath] },
            set: { value in vm.updateElement(elementID) { $0.evidence?[keyPath: keyPath] = value } }
        )
    }

    private func textBinding<Value>(_ keyPath: WritableKeyPath<TextBox, Value>) -> Binding<Value> {
        Binding(
            get: { (vm.element(elementID)?.text ?? TextBox())[keyPath: keyPath] },
            set: { value in vm.updateElement(elementID) { $0.text?[keyPath: keyPath] = value } }
        )
    }

    private func captionBinding(_ itemID: UUID) -> Binding<String> {
        Binding(
            get: { vm.element(elementID)?.evidence?.items.first { $0.id == itemID }?.caption ?? "" },
            set: { value in
                vm.updateElement(elementID) { element in
                    guard let index = element.evidence?.items.firstIndex(where: { $0.id == itemID }) else { return }
                    element.evidence?.items[index].caption = value
                }
            }
        )
    }

    @ViewBuilder
    private func thumbnail(_ item: EvidenceItem) -> some View {
        switch item.kind {
        case .photo:
            if let data = item.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.2))
            }
        case .qr:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                Image(systemName: "qrcode").font(.system(size: 28)).foregroundStyle(.black)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
    }
}

/// Small "title … value" row.
private struct LabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

/// VisionKit document camera: finds the page edges, straightens and crops it.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
