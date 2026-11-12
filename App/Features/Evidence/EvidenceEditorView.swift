import PhotosUI
import SwiftUI

/// Evidence ("الشواهد"): any number of boxes, each on its own page with up to four photos / QR codes,
/// placed and sized freely. Shared by text reports and form reports.
struct EvidenceEditorView: View {
    @ObservedObject var vm: ReportEditorViewModel

    @State private var selectedBlock: UUID?
    @State private var photoTarget: UUID?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var qrTarget: UUID?
    @State private var qrLink = ""
    @State private var qrCaption = ""
    @State private var placing: BlockRef?
    @State private var zoomPage: PageRef?

    struct BlockRef: Identifiable {
        let id: UUID
    }

    private var blocks: [EvidenceBlock] { vm.report.evidenceBlocks }

    private var previewPage: Int {
        let block = blocks.first { $0.id == selectedBlock } ?? blocks.last
        let page = min(block?.page ?? 0, vm.pagination.lastBodyPage)
        return vm.pagination.physicalPage(forBodyPage: page)
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

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                blockSection(index: index, block: block)
            }

            Section {
                Button {
                    selectedBlock = vm.addEvidencePage()
                } label: {
                    Label("صفحة جديدة بمربع شواهد", systemImage: "plus.rectangle.portrait")
                }
                Button {
                    selectedBlock = vm.addEvidenceBlock(page: vm.pagination.lastBodyPage)
                } label: {
                    Label("مربع شواهد في آخر صفحة", systemImage: "plus.square.on.square")
                }
            } footer: {
                Text("كل مربع يتسع لـ ٤ صور أو رموز QR. أضف صفحة جديدة لكل مجموعة شواهد، ويبقى كل مربع في صفحته، ونص التقرير يلتف حوله.")
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: remainingSlots(photoTarget),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty, let target = photoTarget else { return }
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                await vm.addEvidencePhotos(datas, to: target)
                photoItems = []
            }
        }
        .alert("إضافة رمز QR", isPresented: Binding(get: { qrTarget != nil }, set: { if !$0 { qrTarget = nil } })) {
            TextField("الرابط أو النص", text: $qrLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("تعليق تحت الرمز (اختياري)", text: $qrCaption)
            Button("إضافة") {
                if let target = qrTarget { vm.addEvidenceQR(text: qrLink, caption: qrCaption, to: target) }
                qrLink = ""
                qrCaption = ""
                qrTarget = nil
            }
            Button("إلغاء", role: .cancel) { qrTarget = nil }
        } message: {
            Text("يُنشأ الرمز تلقائياً، ويمسحه أي شخص بكاميرا الجوال ليفتح الرابط.")
        }
        .fullScreenCover(item: $placing) { ref in
            if let placement = vm.evidencePlacement(of: ref.id) {
                FreeRectEditor(
                    title: "موضع الشواهد وحجمها",
                    hint: "اسحب المربع لتحريكه، واسحب الزاوية لتغيير حجمه.",
                    physicalPage: vm.pagination.physicalPage(forBodyPage: min(placement.page, vm.pagination.lastBodyPage)),
                    context: vm.renderContext,
                    rect: placement.rect,
                    minimumSize: EvidenceLayout.minimumSize
                ) { rect in
                    vm.setEvidenceRect(ref.id, rect)
                }
            }
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
    }

    // MARK: - One box

    private func blockSection(index: Int, block: EvidenceBlock) -> some View {
        Section {
            ForEach(Array(block.items.enumerated()), id: \.element.id) { itemIndex, item in
                itemRow(item, index: itemIndex, block: block)
            }

            if block.canAddItems {
                Button {
                    selectedBlock = block.id
                    photoTarget = block.id
                    showPhotoPicker = true
                } label: {
                    Label("إضافة صور", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    selectedBlock = block.id
                    qrTarget = block.id
                } label: {
                    Label("إضافة رمز QR من رابط", systemImage: "qrcode")
                }
            }
            if vm.isProcessingImage && photoTarget == block.id {
                HStack {
                    ProgressView()
                    Text("جارٍ تجهيز الصور…").foregroundStyle(.secondary)
                }
            }

            TextField("عنوان المربع (مثل: الشواهد)", text: binding(block.id, \.title))
            Toggle("إطار حول الشواهد", isOn: binding(block.id, \.showBorder))
            Toggle("ملء المربعات بالصور (قص الأطراف)", isOn: binding(block.id, \.fillCells))

            if vm.pagination.bodyPageCount > 1 {
                Stepper(value: pageBinding(block.id), in: 0...max(vm.pagination.lastBodyPage, 0)) {
                    HStack {
                        Text("في الصفحة")
                        Spacer()
                        Text(ArabicFormat.number(block.page + 1, vm.report.page.numerals))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                KeyboardHelper.dismiss()
                selectedBlock = block.id
                vm.repaginate()
                placing = BlockRef(id: block.id)
            } label: {
                Label("تحريك المربع وتغيير حجمه", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .disabled(block.items.isEmpty)

            if block.rect != nil {
                Button("إرجاع الموضع التلقائي") { vm.setEvidenceRect(block.id, nil) }
            }

            Button(role: .destructive) {
                vm.removeEvidenceBlock(block.id)
            } label: {
                Label("حذف هذا المربع", systemImage: "trash")
            }
        } header: {
            Text("مربع الشواهد \(ArabicFormat.number(index + 1, vm.report.page.numerals)) — الصفحة \(ArabicFormat.number(block.page + 1, vm.report.page.numerals)) (\(ArabicFormat.number(block.items.count, vm.report.page.numerals)) من \(ArabicFormat.number(EvidenceBlock.maxItems, vm.report.page.numerals)))")
        }
    }

    private func itemRow(_ item: EvidenceItem, index: Int, block: EvidenceBlock) -> some View {
        HStack(spacing: 12) {
            thumbnail(item)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.kind == .photo ? "صورة \(ArabicFormat.number(index + 1, vm.report.page.numerals))" : "رمز QR")
                    .font(.subheadline.weight(.semibold))
                TextField("تعليق تحت العنصر", text: captionBinding(block.id, item.id))
                    .font(.subheadline)
            }
            Spacer(minLength: 4)
            Menu {
                Button("تقديم") { vm.moveEvidenceItem(item.id, in: block.id, by: -1) }
                    .disabled(index == 0)
                Button("تأخير") { vm.moveEvidenceItem(item.id, in: block.id, by: 1) }
                    .disabled(index == block.items.count - 1)
                Button("حذف", role: .destructive) { vm.removeEvidenceItem(item.id, from: block.id) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func remainingSlots(_ id: UUID?) -> Int {
        let count = blocks.first { $0.id == id }?.items.count ?? 0
        return max(EvidenceBlock.maxItems - count, 1)
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<EvidenceBlock, Value>) -> Binding<Value> {
        Binding(
            get: { (vm.report.evidenceBlocks.first { $0.id == id } ?? EvidenceBlock())[keyPath: keyPath] },
            set: { value in
                var all = vm.report.evidenceBlocks
                if let index = all.firstIndex(where: { $0.id == id }) {
                    all[index][keyPath: keyPath] = value
                    vm.report.evidenceBlocks = all
                }
            }
        )
    }

    private func pageBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { vm.report.evidenceBlocks.first { $0.id == id }?.page ?? 0 },
            set: { vm.setEvidenceBlockPage(id, $0) }
        )
    }

    private func captionBinding(_ blockID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                vm.report.evidenceBlocks.first { $0.id == blockID }?.items.first { $0.id == itemID }?.caption ?? ""
            },
            set: { value in
                var all = vm.report.evidenceBlocks
                guard let blockIndex = all.firstIndex(where: { $0.id == blockID }),
                      let itemIndex = all[blockIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
                all[blockIndex].items[itemIndex].caption = value
                vm.report.evidenceBlocks = all
            }
        )
    }

    @ViewBuilder
    private func thumbnail(_ item: EvidenceItem) -> some View {
        switch item.kind {
        case .photo:
            if let data = item.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.2))
            }
        case .qr:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                Image(systemName: "qrcode")
                    .font(.system(size: 28))
                    .foregroundStyle(.black)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
    }
}
