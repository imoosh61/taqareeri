import PhotosUI
import SwiftUI

/// Evidence ("الشواهد"): up to four photos / QR codes, with free placement on the page.
/// Shared by text reports and form reports.
struct EvidenceEditorView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showQRPrompt = false
    @State private var qrLink = ""
    @State private var qrCaption = ""
    @State private var showPlacement = false
    @State private var zoomPage: PageRef?

    private var evidencePage: Int {
        vm.evidencePlacement()?.page ?? vm.report.evidence.pageIndex
    }

    private var physicalPage: Int {
        vm.pagination.physicalPage(forBodyPage: min(evidencePage, vm.pagination.lastBodyPage))
    }

    var body: some View {
        Form {
            Section {
                A4PageView(page: physicalPage, context: vm.renderContext)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .onTapGesture { zoomPage = PageRef(id: physicalPage) }
            }
            .listRowBackground(Color.clear)

            Section {
                Toggle("إظهار الشواهد في التقرير", isOn: $vm.report.evidence.isEnabled)
            } footer: {
                Text("أضف حتى ٤ صور أو رموز QR (مثلاً رابط مجلد صور في Drive)، ثم حرّك المربع وغيّر حجمه كما تريد.")
            }

            if vm.report.evidence.isEnabled {
                itemsSection
                appearanceSection
                placementSection
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                await vm.addEvidencePhotos(datas)
                photoItems = []
            }
        }
        .alert("إضافة رمز QR", isPresented: $showQRPrompt) {
            TextField("الرابط أو النص", text: $qrLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("تعليق تحت الرمز (اختياري)", text: $qrCaption)
            Button("إضافة") {
                vm.addEvidenceQR(text: qrLink, caption: qrCaption)
                qrLink = ""
                qrCaption = ""
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يُنشأ الرمز تلقائياً، ويمسحه أي شخص بكاميرا الجوال ليفتح الرابط.")
        }
        .fullScreenCover(isPresented: $showPlacement) {
            EvidencePlacementEditor(vm: vm)
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
    }

    // MARK: - Sections

    private var itemsSection: some View {
        Section {
            ForEach(Array(vm.report.evidence.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    thumbnail(item)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kind == .photo ? "صورة \(ArabicFormat.number(index + 1, vm.report.page.numerals))" : "رمز QR")
                            .font(.subheadline.weight(.semibold))
                        TextField("تعليق تحت العنصر", text: captionBinding(item.id))
                            .font(.subheadline)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("تقديم") { vm.moveEvidence(item.id, by: -1) }
                            .disabled(index == 0)
                        Button("تأخير") { vm.moveEvidence(item.id, by: 1) }
                            .disabled(index == vm.report.evidence.items.count - 1)
                        Button("حذف", role: .destructive) { vm.removeEvidence(item.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
                .padding(.vertical, 2)
            }

            if vm.canAddEvidence {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: EvidenceSettings.maxItems - vm.report.evidence.items.count,
                    matching: .images
                ) {
                    Label("إضافة صور", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    showQRPrompt = true
                } label: {
                    Label("إضافة رمز QR من رابط", systemImage: "qrcode")
                }
            }
            if vm.isProcessingImage {
                HStack {
                    ProgressView()
                    Text("جارٍ تجهيز الصور…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("العناصر (\(ArabicFormat.number(vm.report.evidence.items.count, vm.report.page.numerals)) من \(ArabicFormat.number(EvidenceSettings.maxItems, vm.report.page.numerals)))")
        }
    }

    private var appearanceSection: some View {
        Section("الشكل") {
            TextField("عنوان المربع (مثل: الشواهد)", text: $vm.report.evidence.title)
            Toggle("إطار حول الشواهد", isOn: $vm.report.evidence.showBorder)
            Toggle("ملء المربعات بالصور (قص الأطراف)", isOn: $vm.report.evidence.fillCells)
        }
    }

    private var placementSection: some View {
        Section {
            Button {
                vm.addEvidencePage()
            } label: {
                Label("إضافة صفحة جديدة للشواهد", systemImage: "plus.rectangle.portrait")
            }
            if vm.pagination.bodyPageCount > 1 {
                Stepper(value: pageBinding, in: 0...max(vm.pagination.lastBodyPage, 0)) {
                    HStack {
                        Text("في الصفحة")
                        Spacer()
                        Text(ArabicFormat.number(vm.report.evidence.pageIndex + 1, vm.report.page.numerals))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                KeyboardHelper.dismiss()
                vm.repaginate()
                showPlacement = true
            } label: {
                Label("تحريك المربع وتغيير حجمه", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .disabled(vm.report.evidence.items.isEmpty)
            if vm.report.evidence.customRect != nil {
                Button("إرجاع الموضع التلقائي", role: .destructive) {
                    vm.setEvidenceRect(nil)
                }
            }
        } header: {
            Text("الموضع والحجم")
        } footer: {
            if vm.report.kind == .text {
                Text("نص التقرير يلتف حول مربع الشواهد تلقائياً ولا يتداخل معه.")
            }
        }
    }

    // MARK: - Helpers

    private var pageBinding: Binding<Int> {
        Binding(
            get: { vm.report.evidence.pageIndex },
            set: { vm.report.evidence.pageIndex = max($0, 0) }
        )
    }

    private func captionBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { vm.report.evidence.items.first { $0.id == id }?.caption ?? "" },
            set: { value in
                if let index = vm.report.evidence.items.firstIndex(where: { $0.id == id }) {
                    vm.report.evidence.items[index].caption = value
                }
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
                    .font(.system(size: 30))
                    .foregroundStyle(.black)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        }
    }
}
