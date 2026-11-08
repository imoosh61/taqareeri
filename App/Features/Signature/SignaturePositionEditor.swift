import SwiftUI

/// Drag employee signatures and the stamp anywhere on the last page.
/// Tapping an element selects it; the arrow pad nudges the selection for fine positioning.
struct SignaturePositionEditor: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: SignatureElement?
    @State private var dragging: SignatureElement?
    @State private var translation: CGSize = .zero

    private let nudgeStep: CGFloat = 3

    private struct Item: Identifiable {
        let element: SignatureElement
        let rect: CGRect
        let title: String
        var id: SignatureElement { element }
    }

    private var items: [Item] {
        let layout = vm.signatureLayout()
        var result: [Item] = []
        for (index, cell) in layout.employees.enumerated() {
            let employee = vm.report.footer.employees.first { $0.id == cell.id }
            let name = employee?.name.trimmed ?? ""
            result.append(Item(
                element: .employee(cell.id),
                rect: cell.rect,
                title: name.isEmpty ? "موظف \(ArabicFormat.number(index + 1, vm.report.page.numerals))" : name
            ))
        }
        if let stamp = layout.stamp {
            result.append(Item(element: .stamp, rect: stamp, title: "الختم"))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("اسحب أي توقيع أو الختم إلى المكان الذي تريده. اضغط على عنصر لتحديده ثم استخدم الأسهم للضبط الدقيق.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GeometryReader { proxy in
                    let pageWidth = min(proxy.size.width - 16, (proxy.size.height - 8) * A4.aspectRatio)
                    let scale = pageWidth / A4.size.width
                    let pageHeight = pageWidth / A4.aspectRatio

                    ZStack(alignment: .topLeading) {
                        A4PageView(page: vm.lastBodyPhysicalPage, context: vm.renderContext)
                            .frame(width: pageWidth, height: pageHeight)
                            .onTapGesture { selected = nil }

                        ForEach(items) { item in
                            handle(item, scale: scale)
                        }
                    }
                    .frame(width: pageWidth, height: pageHeight)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 8)

                controls
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .navigationTitle("مكان التوقيعات والختم")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("تلقائي") {
                        vm.resetSignaturePositions()
                        selected = nil
                    }
                    .disabled(!vm.report.footer.hasCustomPositions)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    private func handle(_ item: Item, scale: CGFloat) -> some View {
        let isDragging = dragging == item.element
        let isSelected = selected == item.element || isDragging
        let offset = isDragging ? translation : .zero
        let isStamp = item.element == .stamp

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: isStamp ? item.rect.width * scale / 2 : 6)
                .fill(theme.accent.opacity(isSelected ? 0.16 : 0.06))
            RoundedRectangle(cornerRadius: isStamp ? item.rect.width * scale / 2 : 6)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.2, dash: isSelected ? [] : [5, 3]))
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .offset(y: -10)
                .opacity(isSelected ? 1 : 0.85)
        }
        .frame(width: item.rect.width * scale, height: item.rect.height * scale)
        .position(x: item.rect.midX * scale + offset.width, y: item.rect.midY * scale + offset.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    dragging = item.element
                    selected = item.element
                    translation = value.translation
                }
                .onEnded { value in
                    vm.moveSignatureElement(
                        item.element,
                        by: CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                    )
                    dragging = nil
                    translation = .zero
                }
        )
        .simultaneousGesture(TapGesture().onEnded { selected = item.element })
        .zIndex(isSelected ? 1 : 0)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            if let selected, let item = items.first(where: { $0.element == selected }) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 110)
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 44, height: 44)
                        nudgeButton("chevron.up", dx: 0, dy: -nudgeStep)
                        Color.clear.frame(width: 44, height: 44)
                    }
                    GridRow {
                        nudgeButton("chevron.left", dx: -nudgeStep, dy: 0)
                        nudgeButton("chevron.down", dx: 0, dy: nudgeStep)
                        nudgeButton("chevron.right", dx: nudgeStep, dy: 0)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                Text("اختر عنصراً لضبطه بالأسهم")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 94)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func nudgeButton(_ icon: String, dx: CGFloat, dy: CGFloat) -> some View {
        Button {
            if let selected { vm.moveSignatureElement(selected, by: CGSize(width: dx, height: dy)) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}
