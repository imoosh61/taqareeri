import SwiftUI
import UIKit

/// "مربعات نص": free text boxes placed anywhere on any page (text and form reports).
struct TextBoxesView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var placing: TextBoxRef?
    @State private var zoomPage: PageRef?

    struct TextBoxRef: Identifiable {
        let id: UUID
    }

    var body: some View {
        Form {
            Section {
                A4PageView(page: previewPage, context: vm.renderContext)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .onTapGesture { zoomPage = PageRef(id: previewPage) }
            }
            .listRowBackground(Color.clear)

            ForEach(Array(vm.report.textBoxes.enumerated()), id: \.element.id) { index, box in
                boxSection(index: index, box: box)
            }

            Section {
                Button {
                    vm.addTextBox()
                } label: {
                    Label("إضافة مربع نص", systemImage: "character.textbox")
                }
            } footer: {
                Text("ضع المربع في أي مكان من الصفحة: ملاحظة، عنوان إضافي، عبارة «سري»، رقم صادر… المربع يظهر فوق الصفحة ولا يحرّك نص التقرير.")
            }
        }
        .fullScreenCover(item: $placing) { ref in
            if let box = vm.report.textBoxes.first(where: { $0.id == ref.id }) {
                FreeRectEditor(
                    title: "مكان مربع النص",
                    hint: "اسحب المربع لتحريكه، واسحب الزاوية لتغيير حجمه.",
                    physicalPage: vm.pagination.physicalPage(forBodyPage: min(box.page, vm.pagination.lastBodyPage)),
                    context: vm.renderContext,
                    rect: box.rect,
                    minimumSize: TextBox.minimumSize
                ) { rect in
                    vm.setTextBoxRect(ref.id, rect)
                }
            }
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
    }

    private var previewPage: Int {
        let page = vm.report.textBoxes.last?.page ?? 0
        return vm.pagination.physicalPage(forBodyPage: min(page, vm.pagination.lastBodyPage))
    }

    private func boxSection(index: Int, box: TextBox) -> some View {
        Section {
            TextField("النص", text: binding(box.id, \.text), axis: .vertical)
                .lineLimit(1...6)

            FontSizeSlider(
                title: "حجم الخط",
                value: binding(box.id, \.fontSize),
                defaultValue: 14,
                numerals: vm.report.page.numerals,
                range: 8...40
            )

            Toggle("عريض", isOn: binding(box.id, \.bold))
            Toggle("إطار حول المربع", isOn: binding(box.id, \.showBorder))

            Picker("المحاذاة", selection: binding(box.id, \.alignment)) {
                ForEach([ParagraphAlignment.left, .center, .right]) { item in
                    Image(systemName: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .environment(\.layoutDirection, .leftToRight)

            ColorPicker("لون النص", selection: colorBinding(box.id), supportsOpacity: false)

            if vm.report.kind == .text {
                Stepper(value: pageBinding(box.id), in: 0...max(vm.pagination.lastBodyPage, 0)) {
                    HStack {
                        Text("في الصفحة")
                        Spacer()
                        Text(ArabicFormat.number(box.page + 1, vm.report.page.numerals))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                KeyboardHelper.dismiss()
                vm.repaginate()
                placing = TextBoxRef(id: box.id)
            } label: {
                Label("تحريك المربع وتغيير حجمه", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }

            Button(role: .destructive) {
                vm.removeTextBox(box.id)
            } label: {
                Label("حذف المربع", systemImage: "trash")
            }
        } header: {
            Text("مربع نص \(ArabicFormat.number(index + 1, vm.report.page.numerals))")
        }
    }

    // MARK: - Bindings

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<TextBox, Value>) -> Binding<Value> {
        Binding(
            get: { (vm.report.textBoxes.first { $0.id == id } ?? TextBox())[keyPath: keyPath] },
            set: { value in
                var boxes = vm.report.textBoxes
                if let index = boxes.firstIndex(where: { $0.id == id }) {
                    boxes[index][keyPath: keyPath] = value
                    vm.report.textBoxes = boxes
                }
            }
        )
    }

    private func pageBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { vm.report.textBoxes.first { $0.id == id }?.page ?? 0 },
            set: { vm.setTextBoxPage(id, $0) }
        )
    }

    private func colorBinding(_ id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: vm.report.textBoxes.first { $0.id == id }?.colorHex ?? "000000") },
            set: { color in
                var boxes = vm.report.textBoxes
                if let index = boxes.firstIndex(where: { $0.id == id }) {
                    boxes[index].colorHex = UIColor(color).hexString
                    vm.report.textBoxes = boxes
                }
            }
        )
    }
}
