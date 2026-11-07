import UIKit

/// Decorative vector frames. Ornaments are drawn once in a local coordinate space and
/// placed on every corner / edge with transforms, so all four sides stay symmetric.
@MainActor
enum OrnateFrames {
    // MARK: - Placement helpers

    /// Runs `body` for each corner of `rect` with the origin at the corner and +x/+y pointing inward.
    private static func forEachCorner(_ rect: CGRect, _ ctx: CGContext, _ body: () -> Void) {
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1)
        ]
        for (point, sx, sy) in corners {
            ctx.saveGState()
            ctx.translateBy(x: point.x, y: point.y)
            ctx.scaleBy(x: sx, y: sy)
            body()
            ctx.restoreGState()
        }
    }

    /// Runs `body` for each edge of `rect`: local x runs 0…length along the edge, y = 0 on the edge, +y inward.
    private static func forEachEdge(_ rect: CGRect, _ ctx: CGContext, _ body: (CGFloat) -> Void) {
        let edges: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 0, rect.width),
            (CGPoint(x: rect.maxX, y: rect.minY), .pi / 2, rect.height),
            (CGPoint(x: rect.maxX, y: rect.maxY), .pi, rect.width),
            (CGPoint(x: rect.minX, y: rect.maxY), -.pi / 2, rect.height)
        ]
        for (origin, angle, length) in edges {
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.rotate(by: angle)
            body(length)
            ctx.restoreGState()
        }
    }

    /// Evenly spaced positions along a length, keeping `inset` clear at both ends.
    private static func positions(length: CGFloat, spacing: CGFloat, inset: CGFloat) -> [CGFloat] {
        let usable = length - inset * 2
        guard usable > spacing else { return [] }
        let count = Int(usable / spacing)
        let step = usable / CGFloat(count)
        return (0..<count).map { inset + step * (CGFloat($0) + 0.5) }
    }

    private static func clear(_ rect: CGRect, _ ctx: CGContext, restoring color: UIColor) {
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(color.cgColor)
    }

    private static func ellipse(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        ctx.fillEllipse(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        ctx.restoreGState()
    }

    private static func dot(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    // MARK: - Najdi (sawtooth triangles)

    static func najdi(_ page: CGRect, _ ctx: CGContext) {
        ctx.stroke(page.insetBy(dx: 18, dy: 18), width: 1.2)
        ctx.stroke(page.insetBy(dx: 21, dy: 21), width: 0.5)
        ctx.stroke(page.insetBy(dx: 35, dy: 35), width: 0.5)
        ctx.stroke(page.insetBy(dx: 38, dy: 38), width: 1.2)

        let band = page.insetBy(dx: 21, dy: 21)
        forEachEdge(band, ctx) { length in
            for x in positions(length: length, spacing: 14, inset: 16) {
                ctx.move(to: CGPoint(x: x - 7, y: 0))
                ctx.addLine(to: CGPoint(x: x + 7, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: 14))
                ctx.closePath()
            }
            ctx.fillPath()
        }
        forEachCorner(band, ctx) {
            ctx.fill(CGRect(x: 0, y: 0, width: 14, height: 14))
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: 7, y: 7), radius: 4.5))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: - Interlaced circles

    static func interlace(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        ctx.stroke(page.insetBy(dx: 16, dy: 16), width: 1.4)
        ctx.stroke(page.insetBy(dx: 40, dy: 40), width: 1.4)

        let band = page.insetBy(dx: 28, dy: 28)
        ctx.setLineWidth(0.8)
        forEachEdge(band, ctx) { length in
            for x in positions(length: length, spacing: 12, inset: 20) {
                ctx.addEllipse(in: CGRect(x: x - 9, y: -9, width: 18, height: 18))
            }
            ctx.strokePath()
        }
        forEachCorner(band, ctx) {
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: -13, y: -13, width: 26, height: 26))
            ctx.restoreGState()
            ctx.fillEllipse(in: CGRect(x: -11, y: -11, width: 22, height: 22))
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(FrameDrawer.star(center: .zero, radius: 7))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: - Zellige (mosaic of stars and diamonds)

    static func zellige(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        ctx.stroke(page.insetBy(dx: 16, dy: 16), width: 1.2)
        ctx.stroke(page.insetBy(dx: 40, dy: 40), width: 1.2)

        let band = page.insetBy(dx: 28, dy: 28)
        forEachEdge(band, ctx) { length in
            for (index, x) in positions(length: length, spacing: 13, inset: 22).enumerated() {
                if index.isMultiple(of: 2) {
                    ctx.addPath(FrameDrawer.star(center: CGPoint(x: x, y: 0), radius: 6))
                    ctx.fillPath()
                } else {
                    ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: x, y: 0), radius: 3.5))
                    ctx.setLineWidth(0.9)
                    ctx.strokePath()
                }
            }
        }
        forEachCorner(band, ctx) {
            ctx.fill(CGRect(x: -12, y: -12, width: 24, height: 24))
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(FrameDrawer.star(center: .zero, radius: 8))
            ctx.fillPath()
            ctx.restoreGState()
            dot(ctx, .zero, 2.2)
        }
    }

    // MARK: - Arches (mihrab scallops)

    static func arches(_ page: CGRect, _ ctx: CGContext) {
        ctx.stroke(page.insetBy(dx: 18, dy: 18), width: 1.4)
        ctx.stroke(page.insetBy(dx: 36, dy: 36), width: 0.6)

        let line = page.insetBy(dx: 22, dy: 22)
        ctx.stroke(line, width: 0.6)
        forEachEdge(line, ctx) { length in
            let centers = positions(length: length, spacing: 14, inset: 18)
            for x in centers {
                for step in 0...12 {
                    let theta = CGFloat(step) / 12 * .pi
                    let point = CGPoint(x: x + cos(theta) * 7, y: sin(theta) * 7)
                    if step == 0 { ctx.move(to: point) } else { ctx.addLine(to: point) }
                }
            }
            ctx.setLineWidth(0.9)
            ctx.strokePath()
            for x in centers {
                dot(ctx, CGPoint(x: x, y: 10), 1.2)
            }
        }
        forEachCorner(line, ctx) {
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 1, y: 1, width: 18, height: 18))
            ctx.restoreGState()
            ctx.addPath(FrameDrawer.star(center: CGPoint(x: 6, y: 6), radius: 9))
            ctx.fillPath()
        }
    }

    // MARK: - Arabesque (curling corners and side medallions)

    static func arabesque(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        let outer = page.insetBy(dx: 22, dy: 22)
        ctx.stroke(outer, width: 1.4)
        ctx.stroke(page.insetBy(dx: 27, dy: 27), width: 0.6)

        forEachCorner(outer, ctx) {
            clear(CGRect(x: 2, y: 2, width: 58, height: 58), ctx, restoring: color)
            ctx.setLineWidth(1.3)
            // Concentric quarter arcs
            for radius: CGFloat in [44, 34] {
                for step in 0...16 {
                    let theta = CGFloat(step) / 16 * (.pi / 2)
                    let point = CGPoint(x: cos(theta) * radius, y: sin(theta) * radius)
                    if step == 0 { ctx.move(to: point) } else { ctx.addLine(to: point) }
                }
            }
            ctx.strokePath()
            // S-curl flourishes along both edges
            ctx.setLineWidth(1.1)
            ctx.move(to: CGPoint(x: 44, y: 0))
            ctx.addCurve(to: CGPoint(x: 66, y: 8), control1: CGPoint(x: 52, y: 10), control2: CGPoint(x: 60, y: 12))
            ctx.move(to: CGPoint(x: 0, y: 44))
            ctx.addCurve(to: CGPoint(x: 8, y: 66), control1: CGPoint(x: 10, y: 52), control2: CGPoint(x: 12, y: 60))
            ctx.strokePath()
            dot(ctx, CGPoint(x: 67, y: 6), 2.4)
            dot(ctx, CGPoint(x: 6, y: 67), 2.4)
            // Leaves and center bud
            ellipse(ctx, center: CGPoint(x: 18, y: 18), width: 22, height: 9, angle: .pi / 4)
            ellipse(ctx, center: CGPoint(x: 30, y: 9), width: 12, height: 5, angle: .pi / 10)
            ellipse(ctx, center: CGPoint(x: 9, y: 30), width: 12, height: 5, angle: .pi / 2 - .pi / 10)
            dot(ctx, CGPoint(x: 6, y: 6), 3.5)
        }

        forEachEdge(outer, ctx) { length in
            let mid = length / 2
            clear(CGRect(x: mid - 34, y: -4, width: 68, height: 20), ctx, restoring: color)
            ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: mid, y: 5), radius: 8))
            ctx.fillPath()
            ellipse(ctx, center: CGPoint(x: mid - 18, y: 5), width: 16, height: 5, angle: 0)
            ellipse(ctx, center: CGPoint(x: mid + 18, y: 5), width: 16, height: 5, angle: 0)
            dot(ctx, CGPoint(x: mid - 30, y: 5), 2)
            dot(ctx, CGPoint(x: mid + 30, y: 5), 2)
        }
    }

    // MARK: - Floral vine

    static func floral(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        ctx.stroke(page.insetBy(dx: 18, dy: 18), width: 1)
        ctx.stroke(page.insetBy(dx: 40, dy: 40), width: 1)

        let band = page.insetBy(dx: 29, dy: 29)
        forEachEdge(band, ctx) { length in
            let start: CGFloat = 26
            let end = length - 26
            guard end > start else { return }
            let wavelength: CGFloat = 28
            let amplitude: CGFloat = 4
            var x = start
            ctx.move(to: CGPoint(x: x, y: 0))
            while x < end {
                x = min(x + 1.5, end)
                ctx.addLine(to: CGPoint(x: x, y: sin((x - start) / wavelength * 2 * .pi) * amplitude))
            }
            ctx.setLineWidth(0.9)
            ctx.strokePath()

            var leafX = start + wavelength / 4
            var up = true
            while leafX < end {
                let y = (up ? -1 : 1) * amplitude
                ellipse(ctx, center: CGPoint(x: leafX, y: y + (up ? -3 : 3)), width: 9, height: 4, angle: up ? -.pi / 5 : .pi / 5)
                leafX += wavelength / 2
                up.toggle()
            }
        }
        forEachCorner(band, ctx) {
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: -14, y: -14, width: 28, height: 28))
            ctx.restoreGState()
            for petal in 0..<8 {
                let angle = CGFloat(petal) * .pi / 4
                ellipse(ctx, center: CGPoint(x: cos(angle) * 7, y: sin(angle) * 7), width: 10, height: 5, angle: angle)
            }
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            dot(ctx, .zero, 3.4)
            ctx.restoreGState()
            dot(ctx, .zero, 1.8)
        }
    }

    // MARK: - Royal gold corners

    static func goldCorners(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        let outer = page.insetBy(dx: 20, dy: 20)
        ctx.stroke(outer, width: 1)
        ctx.stroke(page.insetBy(dx: 30, dy: 30), width: 0.7)

        forEachCorner(outer, ctx) {
            ctx.fill(CGRect(x: 0, y: 0, width: 78, height: 6))
            ctx.fill(CGRect(x: 0, y: 0, width: 6, height: 78))
            ctx.fill(CGRect(x: 12, y: 12, width: 46, height: 2.5))
            ctx.fill(CGRect(x: 12, y: 12, width: 2.5, height: 46))
            ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: 24, y: 24), radius: 6.5))
            ctx.fillPath()
            for offset: CGFloat in [36, 46, 56] {
                dot(ctx, CGPoint(x: offset * 0.62, y: offset * 0.62 + 12), 1.4)
                dot(ctx, CGPoint(x: offset * 0.62 + 12, y: offset * 0.62), 1.4)
            }
            ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: 84, y: 3), radius: 3.5))
            ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: 3, y: 84), radius: 3.5))
            ctx.fillPath()
        }

        forEachEdge(outer, ctx) { length in
            let mid = length / 2
            clear(CGRect(x: mid - 26, y: 1, width: 52, height: 10), ctx, restoring: color)
            ctx.addPath(FrameDrawer.star(center: CGPoint(x: mid, y: 5), radius: 7))
            ctx.fillPath()
            ctx.fill(CGRect(x: mid - 24, y: 4, width: 14, height: 1.5))
            ctx.fill(CGRect(x: mid + 10, y: 4, width: 14, height: 1.5))
        }
    }

    // MARK: - Royal cartouche

    static func royal(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        ctx.stroke(page.insetBy(dx: 18, dy: 18), width: 2.4)
        ctx.stroke(page.insetBy(dx: 23, dy: 23), width: 0.6)
        let inner = page.insetBy(dx: 27, dy: 27)
        ctx.stroke(inner, width: 1.2)

        forEachCorner(page.insetBy(dx: 23, dy: 23), ctx) {
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: -3, y: -3, width: 10, height: 10))
            ctx.restoreGState()
            ctx.addPath(FrameDrawer.diamond(center: .zero, radius: 7))
            ctx.fillPath()
        }

        // Cartouches centered on the top and bottom edges
        let top = CGPoint(x: page.midX, y: page.minY + 23)
        let bottom = CGPoint(x: page.midX, y: page.maxY - 23)
        for center in [top, bottom] {
            let box = CGRect(x: center.x - 52, y: center.y - 11, width: 104, height: 22)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 11)
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(shape.cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(shape.cgPath)
            ctx.setLineWidth(1.2)
            ctx.strokePath()
            let innerBox = UIBezierPath(roundedRect: box.insetBy(dx: 4, dy: 4), cornerRadius: 7)
            ctx.addPath(innerBox.cgPath)
            ctx.setLineWidth(0.5)
            ctx.strokePath()
            ctx.addPath(FrameDrawer.star(center: center, radius: 6))
            ctx.fillPath()
            for side: CGFloat in [-1, 1] {
                ctx.addPath(FrameDrawer.diamond(center: CGPoint(x: center.x + side * 22, y: center.y), radius: 3))
            }
            ctx.fillPath()
            for side: CGFloat in [-1, 1] {
                dot(ctx, CGPoint(x: center.x + side * 36, y: center.y), 1.6)
            }
        }

        // Small medallions on the side edges
        for x in [page.minX + 23, page.maxX - 23] {
            let center = CGPoint(x: x, y: page.midY)
            ctx.saveGState()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
            ctx.restoreGState()
            ctx.addEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.addPath(FrameDrawer.star(center: center, radius: 5))
            ctx.fillPath()
        }
    }
}
