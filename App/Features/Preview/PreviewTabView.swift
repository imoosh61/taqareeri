import SwiftUI

/// Final review of every page (cover + body), with export.
struct PreviewTabView: View {
    @ObservedObject var vm: ReportEditorViewModel
    let onExport: () -> Void
    @State private var zoomPage: PageRef?
    @State private var columns = 1
    @State private var pendingDeletion: PageRef?
    @State private var info: String?

    var body: some View {
        let total = vm.pagination.totalPages
        VStack(spacing: 0) {
            HStack {
                Label("\(ArabicFormat.number(total, vm.report.page.numerals)) صفحة", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    Button {
                        vm.addPage()
                    } label: {
                        Label("إضافة صفحة فارغة", systemImage: "plus.rectangle.portrait")
                    }
                    Button(role: .destructive) {
                        vm.removeLastPage()
                    } label: {
                        Label("حذف آخر صفحة فارغة", systemImage: "minus.rectangle")
                    }
                    .disabled(!vm.canRemoveLastPage)
                } label: {
                    Label("الصفحات", systemImage: "plus.rectangle.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                }
                Picker("العرض", selection: $columns) {
                    Image(systemName: "rectangle.portrait").tag(1)
                    Image(systemName: "square.grid.2x2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
                    spacing: 22
                ) {
                    ForEach(0..<total, id: \.self) { page in
                        VStack(spacing: 6) {
                            A4PageView(page: page, context: vm.renderContext)
                                .onTapGesture { zoomPage = PageRef(id: page) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        requestDeletion(page)
                                    } label: {
                                        Label("حذف هذه الصفحة", systemImage: "trash")
                                    }
                                }
                            HStack(spacing: 10) {
                                Text(caption(for: page))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    requestDeletion(page)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("حذف هذه الصفحة")
                            }
                        }
                    }
                }
                .padding(.horizontal, columns == 1 ? 28 : 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGray5))

            Button(action: onExport) {
                Label("تصدير PDF ومشاركة", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .safeAreaInset(edge: .top) {
            if vm.canUndoPageDeletion {
                Button {
                    vm.undoPageDeletion()
                } label: {
                    Label("تراجع عن حذف الصفحة", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top, 4)
            }
        }
        .confirmationDialog(
            "حذف الصفحة \(pendingDeletion.map { ArabicFormat.number($0.id + 1, vm.report.page.numerals) } ?? "")؟",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("حذف الصفحة", role: .destructive) {
                if let page = pendingDeletion { vm.deletePage(physical: page.id) }
                pendingDeletion = nil
            }
            Button("إلغاء", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("سيُحذف ما في الصفحة من نص وشواهد ومربعات نص، وتتقدّم الصفحات التالية.")
        }
        .alert(info ?? "", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("حسناً", role: .cancel) {}
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
    }

    private func requestDeletion(_ page: Int) {
        switch vm.deletion(forPhysicalPage: page) {
        case .allowed:
            pendingDeletion = PageRef(id: page)
        case .cover:
            info = "لإزالة صفحة الغلاف أوقف «صفحة غلاف رسمية» من تبويب «الترويسة»."
        case .formFirstPage:
            info = "الصفحة الأولى تحتوي حقول النموذج ولا يمكن حذفها."
        case .onlyPage:
            info = "لا يمكن حذف الصفحة الوحيدة في التقرير."
        case .signaturesOnly:
            info = "هذه الصفحة للتوقيعات فقط وتُنشأ تلقائياً. تختفي إذا قلّ المحتوى في الصفحة السابقة، أو إذا أوقفت التوقيعات أو صغّرت الشواهد."
        }
    }

    private func caption(for page: Int) -> String {
        if vm.pagination.kind(ofPage: page) == .cover { return "الغلاف" }
        return vm.pageLabel(forPhysicalPage: page)
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
                ForEach(0..<vm.pagination.totalPages, id: \.self) { page in
                    ZoomablePage(context: vm.renderContext, page: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGray5))
            .navigationTitle(vm.pageLabel(forPhysicalPage: selection))
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
    let context: PageRenderContext
    let page: Int
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - 32) * scale * pinch
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                A4PageView(page: page, context: context)
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
