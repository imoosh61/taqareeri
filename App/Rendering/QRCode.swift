import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// QR code as a module matrix, drawn as vector squares (sharp in print and PDF).
struct QRMatrix {
    let size: Int
    let modules: [Bool]

    static func make(_ text: String) -> QRMatrix? {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, width == height,
              let cgImage = CIContext(options: nil).createCGImage(output, from: extent) else { return nil }

        // Draw into a known RGBA buffer (row 0 = top) and read dark modules.
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let modules = (0..<(width * height)).map { pixels[$0 * 4] < 128 }
        return QRMatrix(size: width, modules: modules)
    }

    /// Draws the code (with a quiet zone) as large as fits, centered in `rect`.
    func draw(in rect: CGRect, context ctx: CGContext) {
        let quiet = 2
        let side = min(rect.width, rect.height)
        guard side > 0, size > 0 else { return }
        let cell = side / CGFloat(size + quiet * 2)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)

        ctx.saveGState()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: origin, size: CGSize(width: side, height: side)))
        ctx.setFillColor(UIColor.black.cgColor)
        for row in 0..<size {
            for column in 0..<size where modules[row * size + column] {
                ctx.addRect(CGRect(
                    x: origin.x + CGFloat(column + quiet) * cell,
                    y: origin.y + CGFloat(row + quiet) * cell,
                    width: cell + 0.01,
                    height: cell + 0.01
                ))
            }
        }
        ctx.fillPath()
        ctx.restoreGState()
    }
}
