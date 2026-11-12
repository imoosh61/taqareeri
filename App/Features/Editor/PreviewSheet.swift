import SwiftUI

/// Final review exactly as the PDF will look, with page deletion and export.
struct PreviewSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    let onExport: (ExportFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoomPage: PageRef?
    @State private var pendingDeletion: PageRef?
    @State private var columns = 2
    @State private var trashTargeted = false
    @State private var dropTarget: Int?

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
                                    .overlay {
                                        if dropTarget == page {
                                            RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 3)
                                        }
                                    }
                                    .draggable(PageDragToken.encode(page)) {
                                        A4PageView(page: page, snapshot: vm.snapshot).frame(width: 110)
                                    }
                                    .dropDestination(for: String.self) { items, _ in
                                        dropTarget = nil
                                        guard let source = items.first.flatMap(PageDragToken.decode) else { return false }
                                        vm.movePage(from: source, to: page)
                                        return true
                                    } isTargeted: { targeted in
                                        if targeted { dropTarget = page } else if dropTarget == page { dropTarget = nil }
                                    }
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

                VStack(spacing: 10) {
                    if vm.canDeletePages {
                        trashZone
                    }
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                            onExport(.pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            dismiss()
                            onExport(.images)
                        } label: {
                            Label("صور JPG", systemImage: "photo")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("المعاينة والتصدير")
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

extension PreviewSheet {
    /// Drop a page here (long-press then drag) to delete it.
    private var trashZone: some View {
        HStack(spacing: 8) {
            Image(systemName: trashTargeted ? "trash.fill" : "trash")
            Text(trashTargeted ? "أفلت للحذف" : "اضغط مطولاً على صفحة واسحبها هنا لحذفها، أو فوق صفحة أخرى لتغيير ترتيبها")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(trashTargeted ? Color.white : Color.red)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(trashTargeted ? Color.red : Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .dropDestination(for: String.self) { items, _ in
            trashTargeted = false
            guard let page = items.first.flatMap(PageDragToken.decode) else { return false }
            pendingDeletion = PageRef(id: page)
            return true
        } isTargeted: { trashTargeted = $0 }
        .animation(.easeInOut(duration: 0.15), value: trashTargeted)
    }
}

/// Pages are dragged as a short text token (only meaningful inside this screen).
enum PageDragToken {
    static let prefix = "taqareeri-page:"

    static func encode(_ page: Int) -> String { prefix + String(page) }

    static func decode(_ token: String) -> Int? {
        guard token.hasPrefix(prefix) else { return nil }
        return Int(token.dropFirst(prefix.count))
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
