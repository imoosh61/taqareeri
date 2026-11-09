import SwiftUI

/// Drag the evidence box anywhere on its page and resize it from the corner handle.
struct EvidencePlacementEditor: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var moveOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var isInteracting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("اسحب المربع لتحريكه، واسحب الزاوية لتغيير حجمه.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let placement = vm.evidencePlacement() {
                    GeometryReader { proxy in
                        let pageWidth = min(proxy.size.width - 16, (proxy.size.height - 8) * A4.aspectRatio)
                        let scale = pageWidth / A4.size.width
                        let pageHeight = pageWidth / A4.aspectRatio

                        ZStack(alignment: .topLeading) {
                            A4PageView(page: vm.pagination.physicalPage(forBodyPage: min(placement.page, vm.pagination.lastBodyPage)),
                                       context: vm.renderContext)
                                .frame(width: pageWidth, height: pageHeight)

                            box(placement.rect, scale: scale)
                        }
                        .frame(width: pageWidth, height: pageHeight)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 8)

                    quickSizes(placement)
                } else {
                    ContentUnavailableView("لا توجد شواهد", systemImage: "photo", description: Text("أضف صورة أو رمز QR أولاً."))
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .navigationTitle("موضع الشواهد وحجمها")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("تلقائي") { vm.setEvidenceRect(nil) }
                        .disabled(vm.report.evidence.customRect == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    private func box(_ rect: CGRect, scale: CGFloat) -> some View {
        let width = max(rect.width * scale + resizeOffset.width, EvidenceLayout.minimumSize.width * scale)
        let height = max(rect.height * scale + resizeOffset.height, EvidenceLayout.minimumSize.height * scale)
        let origin = CGPoint(x: rect.minX * scale + moveOffset.width, y: rect.minY * scale + moveOffset.height)

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.accent.opacity(isInteracting ? 0.18 : 0.08))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: isInteracting ? [] : [6, 3]))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            moveOffset = value.translation
                        }
                        .onEnded { value in
                            commit(rect, scale: scale, move: value.translation, resize: .zero)
                        }
                )

            // Resize handle
            Circle()
                .fill(theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.bold)).foregroundStyle(.white))
                .offset(x: 10, y: 10)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            resizeOffset = value.translation
                        }
                        .onEnded { value in
                            commit(rect, scale: scale, move: .zero, resize: value.translation)
                        }
                )
        }
        .frame(width: width, height: height)
        .offset(x: origin.x, y: origin.y)
    }

    private func commit(_ rect: CGRect, scale: CGFloat, move: CGSize, resize: CGSize) {
        var updated = rect
        updated.origin.x += move.width / scale
        updated.origin.y += move.height / scale
        updated.size.width += resize.width / scale
        updated.size.height += resize.height / scale
        vm.setEvidenceRect(updated)
        moveOffset = .zero
        resizeOffset = .zero
        isInteracting = false
    }

    /// One-tap sizes relative to the page's writing area.
    private func quickSizes(_ placement: EvidenceLayout.Placement) -> some View {
        let body = vm.pagination.spec.bodyRect(bodyPage: placement.page)
        return HStack(spacing: 10) {
            sizeButton("عرض كامل") {
                vm.setEvidenceRect(CGRect(x: body.minX, y: placement.rect.minY, width: body.width, height: placement.rect.height))
            }
            sizeButton("نصف يمين") {
                vm.setEvidenceRect(CGRect(x: body.midX + 5, y: placement.rect.minY, width: body.width / 2 - 5, height: placement.rect.height))
            }
            sizeButton("نصف يسار") {
                vm.setEvidenceRect(CGRect(x: body.minX, y: placement.rect.minY, width: body.width / 2 - 5, height: placement.rect.height))
            }
            sizeButton("توسيط") {
                vm.setEvidenceRect(CGRect(x: body.midX - placement.rect.width / 2, y: placement.rect.minY,
                                          width: placement.rect.width, height: placement.rect.height))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func sizeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
    }
}
