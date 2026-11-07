import UIKit

/// Vector page borders drawn with Core Graphics (stay sharp in the exported PDF).
@MainActor
enum FrameDrawer {
    static func draw(_ style: FrameStyle, color: UIColor, image: UIImage? = nil, in page: CGRect, context ctx: CGContext) {
        guard style != .none else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineJoin(.miter)

        switch style {
        case .none:
            break
        case .customImage:
            if let image {
                UIGraphicsPushContext(ctx)
                image.draw(in: page)
                UIGraphicsPopContext()
            } else {
                ctx.stroke(page.insetBy(dx: 24, dy: 24), width: 1.2)
            }
        case .najdi:
            OrnateFrames.najdi(page, ctx)
        case .interlace:
            OrnateFrames.interlace(page, ctx, color: color)
        case .zellige:
            OrnateFrames.zellige(page, ctx, color: color)
        case .arches:
            OrnateFrames.arches(page, ctx)
        case .arabesque:
            OrnateFrames.arabesque(page, ctx, color: color)
        case .floral:
            OrnateFrames.floral(page, ctx, color: color)
        case .goldCorners:
            OrnateFrames.goldCorners(page, ctx, color: color)
        case .royal:
            OrnateFrames.royal(page, ctx, color: color)
        case .single:
            ctx.stroke(page.insetBy(dx: 24, dy: 24), width: 1.2)
        case .double:
            ctx.stroke(page.insetBy(dx: 22, dy: 22), width: 2.2)
            ctx.stroke(page.insetBy(dx: 28, dy: 28), width: 0.8)
        case .thickThin:
            ctx.stroke(page.insetBy(dx: 20, dy: 20), width: 4.5)
            ctx.stroke(page.insetBy(dx: 28, dy: 28), width: 1)
        case .cornerAccents:
            drawCornerAccents(page, ctx)
        case .geometric:
            drawGeometric(page, ctx)
        case .islamic:
            drawIslamic(page, ctx, color: color)
        case .calm:
            drawCalm(page, ctx, color: color)
        case .dotted:
            drawDotted(page, ctx)
        }
    }

    // MARK: - Styles

    private static func drawCornerAccents(_ page: CGRect, _ ctx: CGContext) {
        let thin = page.insetBy(dx: 28, dy: 28)
        ctx.stroke(thin, width: 0.8)

        let outer = page.insetBy(dx: 20, dy: 20)
        let length: CGFloat = 64
        ctx.setLineWidth(4)
        ctx.setLineCap(.square)
        for corner in corners(of: outer) {
            ctx.move(to: CGPoint(x: corner.point.x + corner.dx * length, y: corner.point.y))
            ctx.addLine(to: corner.point)
            ctx.addLine(to: CGPoint(x: corner.point.x, y: corner.point.y + corner.dy * length))
        }
        ctx.strokePath()

        for corner in corners(of: thin) {
            ctx.addPath(diamond(center: corner.point, radius: 4))
        }
        ctx.fillPath()
    }

    private static func drawGeometric(_ page: CGRect, _ ctx: CGContext) {
        let outer = page.insetBy(dx: 18, dy: 18)
        let inner = page.insetBy(dx: 36, dy: 36)
        let middle = page.insetBy(dx: 27, dy: 27)
        ctx.stroke(outer, width: 1.2)
        ctx.stroke(inner, width: 1.2)

        for point in pointsAlongEdges(middle, spacing: 18, inset: 18) {
            ctx.addPath(diamond(center: point, radius: 4.2))
        }
        ctx.fillPath()

        for corner in corners(of: middle) {
            let square = CGRect(x: corner.point.x - 7, y: corner.point.y - 7, width: 14, height: 14)
            ctx.fill(square)
        }
    }

    private static func drawIslamic(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        ctx.stroke(page.insetBy(dx: 16, dy: 16), width: 1.6)
        ctx.stroke(page.insetBy(dx: 19.5, dy: 19.5), width: 0.5)
        ctx.stroke(page.insetBy(dx: 34.5, dy: 34.5), width: 0.5)
        ctx.stroke(page.insetBy(dx: 38, dy: 38), width: 1.6)

        let band = page.insetBy(dx: 27, dy: 27)
        for point in pointsAlongEdges(band, spacing: 22, inset: 26) {
            ctx.addPath(star(center: point, radius: 5))
        }
        ctx.setLineWidth(0.9)
        ctx.strokePath()

        for corner in corners(of: band) {
            // Clear the crossing lines, then draw a filled rosette.
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: corner.point.x - 12, y: corner.point.y - 12, width: 24, height: 24))
            ctx.setFillColor(color.cgColor)
            ctx.addPath(star(center: corner.point, radius: 11))
            ctx.fillPath()
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(star(center: corner.point, radius: 5))
            ctx.fillPath()
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: corner.point.x - 1.8, y: corner.point.y - 1.8, width: 3.6, height: 3.6))
        }
    }

    private static func drawCalm(_ page: CGRect, _ ctx: CGContext, color: UIColor) {
        let main = UIBezierPath(roundedRect: page.insetBy(dx: 26, dy: 26), cornerRadius: 22)
        ctx.addPath(main.cgPath)
        ctx.setLineWidth(0.9)
        ctx.strokePath()

        let inner = UIBezierPath(roundedRect: page.insetBy(dx: 31, dy: 31), cornerRadius: 18)
        ctx.addPath(inner.cgPath)
        ctx.setStrokeColor(color.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        let r = page.insetBy(dx: 26, dy: 26)
        let midpoints: [(CGPoint, Bool)] = [
            (CGPoint(x: r.midX, y: r.minY), true),
            (CGPoint(x: r.midX, y: r.maxY), true),
            (CGPoint(x: r.minX, y: r.midY), false),
            (CGPoint(x: r.maxX, y: r.midY), false)
        ]
        ctx.setFillColor(UIColor.white.cgColor)
        for (point, horizontal) in midpoints {
            let clear = horizontal
                ? CGRect(x: point.x - 18, y: point.y - 4, width: 36, height: 8)
                : CGRect(x: point.x - 4, y: point.y - 18, width: 8, height: 36)
            ctx.fill(clear)
        }
        ctx.setFillColor(color.cgColor)
        for (point, horizontal) in midpoints {
            for offset in [-10.0, 0.0, 10.0] {
                let center = horizontal
                    ? CGPoint(x: point.x + CGFloat(offset), y: point.y)
                    : CGPoint(x: point.x, y: point.y + CGFloat(offset))
                let radius: CGFloat = offset == 0 ? 2.6 : 1.6
                ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }

    private static func drawDotted(_ page: CGRect, _ ctx: CGContext) {
        let dots = page.insetBy(dx: 23, dy: 23)
        for point in pointsAlongEdges(dots, spacing: 8, inset: 6) {
            ctx.fillEllipse(in: CGRect(x: point.x - 1.3, y: point.y - 1.3, width: 2.6, height: 2.6))
        }
        for corner in corners(of: dots) {
            ctx.fillEllipse(in: CGRect(x: corner.point.x - 3.2, y: corner.point.y - 3.2, width: 6.4, height: 6.4))
        }
        ctx.stroke(page.insetBy(dx: 30, dy: 30), width: 0.5)
    }

    // MARK: - Geometry helpers

    private struct Corner {
        let point: CGPoint
        let dx: CGFloat
        let dy: CGFloat
    }

    private static func corners(of rect: CGRect) -> [Corner] {
        [
            Corner(point: CGPoint(x: rect.minX, y: rect.minY), dx: 1, dy: 1),
            Corner(point: CGPoint(x: rect.maxX, y: rect.minY), dx: -1, dy: 1),
            Corner(point: CGPoint(x: rect.minX, y: rect.maxY), dx: 1, dy: -1),
            Corner(point: CGPoint(x: rect.maxX, y: rect.maxY), dx: -1, dy: -1)
        ]
    }

    /// Evenly distributed points along the four edges of `rect`, keeping `inset` clear at each corner.
    private static func pointsAlongEdges(_ rect: CGRect, spacing: CGFloat, inset: CGFloat) -> [CGPoint] {
        let edges: [(CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY))
        ]
        var points: [CGPoint] = []
        for (start, end) in edges {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let total = hypot(dx, dy)
            let usable = total - inset * 2
            guard total > 0, usable > spacing else { continue }
            let count = Int(usable / spacing)
            let step = usable / CGFloat(count)
            let ux = dx / total
            let uy = dy / total
            for k in 0..<count {
                let distance = inset + step * (CGFloat(k) + 0.5)
                points.append(CGPoint(x: start.x + ux * distance, y: start.y + uy * distance))
            }
        }
        return points
    }

    static func diamond(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }

    /// Eight-pointed star (two overlapping squares, Rub el Hizb outline).
    static func star(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let innerRadius = radius * 0.765
        for index in 0..<16 {
            let angle = CGFloat(index) * .pi / 8 - .pi / 2
            let r = index.isMultiple(of: 2) ? radius : innerRadius
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
