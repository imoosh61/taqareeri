import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case header, frame, writing, fields, evidence, signature, preview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .header: return "الترويسة"
        case .frame: return "الإطار"
        case .writing: return "الكتابة"
        case .fields: return "الحقول"
        case .evidence: return "الشواهد"
        case .signature: return "التوقيع"
        case .preview: return "المعاينة"
        }
    }

    var icon: String {
        switch self {
        case .header: return "rectangle.topthird.inset.filled"
        case .frame: return "square.dashed"
        case .writing: return "text.alignright"
        case .fields: return "list.bullet.rectangle"
        case .evidence: return "photo.on.rectangle"
        case .signature: return "signature"
        case .preview: return "eye"
        }
    }

    static func tabs(for kind: ReportKind) -> [EditorTab] {
        switch kind {
        case .text: return [.header, .frame, .writing, .evidence, .signature, .preview]
        case .form: return [.header, .frame, .fields, .evidence, .signature, .preview]
        }
    }
}

/// Hosts the report journey: header → frame → writing → signature → preview & export.
struct ReportEditorView: View {
    @StateObject private var vm: ReportEditorViewModel
    @State private var tab: EditorTab
    @State private var shareItem: IdentifiedURL?
    @State private var zoomPage: PageRef?
    @Environment(\.scenePhase) private var scenePhase

    init(report: Report, store: ReportStore) {
        _vm = StateObject(wrappedValue: ReportEditorViewModel(report: report, store: store))
        let start: EditorTab
        switch report.kind {
        case .text: start = report.body.isEmpty ? .header : .writing
        case .form: start = .fields
        }
        _tab = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Group {
                switch tab {
                case .header: HeaderEditorView(vm: vm)
                case .frame: FrameGalleryView(vm: vm)
                case .writing: WritingView(vm: vm)
                case .fields: FormFieldsView(vm: vm)
                case .evidence: EvidenceEditorView(vm: vm)
                case .signature: SignatureStampView(vm: vm)
                case .preview: PreviewTabView(vm: vm, onExport: export)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(vm.report.title.trimmed.isEmpty ? "تقرير" : vm.report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    KeyboardHelper.dismiss()
                    vm.autoFormatIfEnabled()
                    vm.repaginate()
                    zoomPage = PageRef(id: tab == .writing ? vm.cursorPhysicalPage : 0)
                } label: {
                    Label("معاينة", systemImage: "eye")
                }
                Button(action: export) {
                    Label("تصدير PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareItem, onDismiss: TempFiles.cleanup) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .alert(
            "تنبيه",
            isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .onChange(of: tab) { oldTab, _ in
            KeyboardHelper.dismiss()
            if oldTab == .writing { vm.autoFormatIfEnabled() }
            vm.saveNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.saveNow() }
        }
        .onDisappear { vm.saveNow() }
    }

    /// Scrollable tab chips (six tabs do not fit a segmented control on a phone).
    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorTab.tabs(for: vm.report.kind)) { item in
                        let selected = tab == item
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(item)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: tab) { _, newTab in
                withAnimation { proxy.scrollTo(newTab, anchor: .center) }
            }
        }
        .background(.bar)
    }

    private func export() {
        KeyboardHelper.dismiss()
        if let url = vm.exportPDF() {
            shareItem = IdentifiedURL(url: url)
        }
    }
}
