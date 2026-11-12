import SwiftUI

/// Final review exactly as the PDF will look, with page deletion and export.
struct PreviewSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoomPage: PageRef?
    @State private var pendingDeletion: PageRef?
    @State private var columns = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if !vm.snapshot.overflowingPages.isEmpty {
                        Label("في بعض الصفحات نص لا يظهر لأنه أطول من الصفحة. ارجع للتحرير واضغط الزر الأحمر أسفل الصفحة لنقله.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 20) {
                        ForEach(0..<vm.snapshot.pageCount, id: \.self) { page in
                            VStack(spacing: 6) {
                                A4PageView(page: page, snapshot: vm.snapshot)
                                    .onTapGesture { zoomPage = PageRef(id: page) }
                                    .overlay(alignment: .topLeading) {
                                        if vm.snapshot.texts[page].overflowLocation != nil {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.white)
                                                .padding(6)
                                                .background(.red, in: Circle())
                                                .padding(6)
                                        }
                                    }
                                HStack {
                                    Text(vm.pageLabel(page)).font(.caption).foregroundStyle(.secondary)
                                    if vm.canDeletePages {
                                        Button {
                                            pendingDeletion = PageRef(id: page)
                                        } label: {
                                            Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("حذف هذه الصفحة")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGray5))

                Button {
                    dismiss()
                    onExport()
                } label: {
                    Label("تصدير PDF ومشاركة", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .navigationTitle("المعاينة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("العرض", selection: $columns) {
                        Image(systemName: "rectangle.portrait").tag(1)
                        Image(systemName: "square.grid.2x2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
            }
            .confirmationDialog(
                "حذف الصفحة \(pendingDeletion.map { ArabicFormat.number($0.id + 1, vm.report.page.numerals) } ?? "")؟",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("حذف الصفحة", role: .destructive) {
                    if let page = pendingDeletion { vm.deletePage(at: page.id) }
                    pendingDeletion = nil
                }
                Button("إلغاء", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("يُحذف نص الصفحة وشواهدها ومربعاتها. يمكنك التراجع بعدها.")
            }
            .sheet(item: $zoomPage) { ref in
                PageZoomSheet(vm: vm, initialPage: ref.id)
            }
            .onAppear { vm.rebuildSnapshot() }
        }
    }
}

/// Full-screen page viewer: swipe between pages, pinch or double-tap to zoom.
struct PageZoomSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss

    init(vm: ReportEditorViewModel, initialPage: Int) {
        self.vm = vm
        _selection = State(initialValue: initialPage)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(0..<vm.snapshot.pageCount, id: \.self) { page in
                    ZoomablePage(snapshot: vm.snapshot, page: page).tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGray5))
            .navigationTitle(vm.pageLabel(selection))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}

private struct ZoomablePage: View {
    let snapshot: DocumentSnapshot
    let page: Int
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - 32) * scale * pinch
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                A4PageView(page: page, snapshot: snapshot)
                    .frame(width: max(width, 100))
                    .padding(16)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 4) }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { scale = scale > 1.2 ? 1 : 2.5 }
            }
        }
    }
}
