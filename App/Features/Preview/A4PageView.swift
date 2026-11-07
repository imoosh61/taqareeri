import SwiftUI
import UIKit

/// UIView that draws one A4 page with the shared `PageRenderer` (identical to the PDF output).
final class PageCanvasView: UIView {
    private var page = 0
    private var context: PageRenderContext?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
        semanticContentAttribute = .forceLeftToRight
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(page: Int, context: PageRenderContext) {
        if let old = self.context,
           old.pagination === context.pagination,
           self.page == page,
           old.report == context.report {
            return
        }
        self.page = page
        self.context = context
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context, let cg = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        guard page < context.pagination.totalPages else {
            UIColor.white.setFill()
            cg.fill(bounds)
            return
        }
        cg.saveGState()
        let scale = bounds.width / A4.size.width
        cg.scaleBy(x: scale, y: scale)
        PageRenderer.draw(page: page, context: context, in: cg)
        cg.restoreGState()
    }
}

private struct PageCanvas: UIViewRepresentable {
    let page: Int
    let context: PageRenderContext

    func makeUIView(context: Context) -> PageCanvasView {
        PageCanvasView(frame: .zero)
    }

    func updateUIView(_ view: PageCanvasView, context: Context) {
        view.update(page: page, context: self.context)
    }
}

/// A4 page with paper styling, sized by aspect ratio.
struct A4PageView: View {
    let page: Int
    let context: PageRenderContext

    var body: some View {
        PageCanvas(page: page, context: context)
            .aspectRatio(A4.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Small frame-only swatch used in the frame gallery.
final class FrameSwatchUIView: UIView {
    var style: FrameStyle = .none { didSet { if style != oldValue { setNeedsDisplay() } } }
    var colorHex = Theme.accentHex { didSet { if colorHex != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        cg.saveGState()
        let scale = bounds.width / A4.size.width
        cg.scaleBy(x: scale, y: scale)
        UIColor.white.setFill()
        cg.fill(A4.bounds)
        FrameDrawer.draw(style, color: UIColor(hex: colorHex), in: A4.bounds, context: cg)

        // Suggested text lines
        cg.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        var y: CGFloat = 200
        while y < A4.size.height - 120 {
            cg.fill(CGRect(x: 80, y: y, width: A4.size.width - 160, height: 9))
            y += 34
        }
        cg.restoreGState()
    }
}

struct FrameSwatch: UIViewRepresentable {
    let style: FrameStyle
    let colorHex: String

    func makeUIView(context: Context) -> FrameSwatchUIView {
        FrameSwatchUIView(frame: .zero)
    }

    func updateUIView(_ view: FrameSwatchUIView, context: Context) {
        view.style = style
        view.colorHex = colorHex
    }
}
