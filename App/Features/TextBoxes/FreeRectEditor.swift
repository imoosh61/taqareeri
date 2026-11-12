import SwiftUI

/// Reusable full-screen editor: shows one page and lets the user drag a box and resize it from
/// its corner. Works in A4 points; the caller decides what the box is and stores the result.
struct FreeRectEditor: View {
    let title: String
    let hint: String
    let physicalPage: Int
    let context: PageRenderContext
    let rect: CGRect
    let minimumSize: CGSize
    let onChange: (CGRect) -> Void

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var moveOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var isInteracting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GeometryReader { proxy in
                    let pageWidth = min(proxy.size.width - 16, (proxy.size.height - 8) * A4.aspectRatio)
                    let scale = pageWidth / A4.size.width
                    let pageHeight = pageWidth / A4.aspectRatio

                    ZStack(alignment: .topLeading) {
                        A4PageView(page: physicalPage, context: context)
                            .frame(width: pageWidth, height: pageHeight)
                        box(scale: scale)
                    }
                    .frame(width: pageWidth, height: pageHeight)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 8)

                nudgePad
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    private func box(scale: CGFloat) -> some View {
        let width = max(rect.width * scale + resizeOffset.width, minimumSize.width * scale)
        let height = max(rect.height * scale + resizeOffset.height, minimumSize.height * scale)

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.accent.opacity(isInteracting ? 0.18 : 0.08))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: isInteracting ? [] : [6, 3]))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            moveOffset = value.translation
                        }
                        .onEnded { value in
                            commit(move: value.translation, resize: .zero, scale: scale)
                        }
                )
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
                            commit(move: .zero, resize: value.translation, scale: scale)
                        }
                )
        }
        .frame(width: width, height: height)
        .offset(x: rect.minX * scale + moveOffset.width, y: rect.minY * scale + moveOffset.height)
    }

    private func commit(move: CGSize, resize: CGSize, scale: CGFloat) {
        var updated = rect
        updated.origin.x += move.width / scale
        updated.origin.y += move.height / scale
        updated.size.width += resize.width / scale
        updated.size.height += resize.height / scale
        onChange(updated)
        moveOffset = .zero
        resizeOffset = .zero
        isInteracting = false
    }

    private var nudgePad: some View {
        HStack(spacing: 8) {
            nudge("chevron.left") { shift(-2, 0) }
            nudge("chevron.up") { shift(0, -2) }
            nudge("chevron.down") { shift(0, 2) }
            nudge("chevron.right") { shift(2, 0) }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func shift(_ dx: CGFloat, _ dy: CGFloat) {
        onChange(rect.offsetBy(dx: dx, dy: dy))
    }

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}
