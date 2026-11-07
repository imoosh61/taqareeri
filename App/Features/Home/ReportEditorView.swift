import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case header, frame, writing, signature, preview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .header: return "الترويسة"
        case .frame: return "الإطار"
        case .writing: return "الكتابة"
        case .signature: return "التوقيع"
        case .preview: return "المعاينة"
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
        _tab = State(initialValue: report.body.isEmpty ? .header : .writing)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("القسم", selection: $tab) {
                ForEach(EditorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case .header: HeaderEditorView(vm: vm)
                case .frame: FrameGalleryView(vm: vm)
                case .writing: WritingView(vm: vm)
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
        .sheet(item: $shareItem) { item in
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
        .onChange(of: tab) {
            KeyboardHelper.dismiss()
            vm.saveNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.saveNow() }
        }
        .onDisappear { vm.saveNow() }
    }

    private func export() {
        KeyboardHelper.dismiss()
        if let url = vm.exportPDF() {
            shareItem = IdentifiedURL(url: url)
        }
    }
}
