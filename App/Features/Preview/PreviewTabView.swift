import SwiftUI

/// Final review of every page (cover + body), with export.
struct PreviewTabView: View {
    @ObservedObject var vm: ReportEditorViewModel
    let onExport: () -> Void
    @State private var zoomPage: PageRef?
    @State private var columns = 1

    var body: some View {
        let total = vm.pagination.totalPages
        VStack(spacing: 0) {
            HStack {
                Label("\(ArabicFormat.number(total, vm.report.page.numerals)) صفحة", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                Spacer()
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
                            Text(caption(for: page))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onTapGesture { zoomPage = PageRef(id: page) }
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
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
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
