import PhotosUI
import SwiftUI
import UIKit

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

    private var element: PageElement? { vm.element(elementID) }

    var body: some View {
        NavigationStack {
            Group {
                if let element {
                    Form {
                        switch element.kind {
                        case .evidence: evidenceSections(element.evidence ?? EvidenceBlock())
                        case .text: textSections()
                        }
                        Section {
                            Button(role: .destructive) {
                                vm.deleteElement(elementID)
                                dismiss()
                            } label: {
                                Label(element.kind == .evidence ? "حذف مربع الشواهد" : "حذف مربع النص", systemImage: "trash")
                            }
                        } footer: {
                            Text("لتحريكه أو تغيير حجمه: اضغط عليه في الصفحة ثم اسحبه أو اسحب زاويته.")
                        }
                    }
                } else {
                    ContentUnavailableView("العنصر غير موجود", systemImage: "questionmark.square.dashed")
                }
            }
            .navigationTitle(element?.kind == .text ? "مربع نص" : "الشواهد")
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
