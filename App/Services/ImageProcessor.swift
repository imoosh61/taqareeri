import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LogoBackgroundMode: String, CaseIterable, Identifiable, Codable {
    case smart, allWhite, keep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "تفريغ ذكي (الخلفية فقط)"
        case .allWhite: return "إزالة كل الأبيض"
        case .keep: return "بدون تفريغ"
        }
    }
}

enum ImageProcessingError: LocalizedError {
    case unreadable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return "تعذر قراءة الصورة."
        case .encodingFailed: return "تعذر معالجة الصورة."
        }
    }
}

/// Logo / stamp / signature preparation: orientation fix + downscale (ImageIO),
/// then white background removal on raw RGBA pixels. Pure Core Graphics → safe off the main thread.
enum ImageProcessor {
    /// Pixels at or above this whiteness become fully transparent.
    private static let solidThreshold = 236
    /// Pixels between soft and solid thresholds fade out (anti-aliased edges).
    private static let softThreshold = 206

    static func process(_ data: Data, mode: LogoBackgroundMode, maxPixelSize: Int = 1000) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try ImageProcessor.processSync(data, mode: mode, maxPixelSize: maxPixelSize)
        }.value
    }

    static func processSync(_ data: Data, mode: LogoBackgroundMode, maxPixelSize: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageProcessingError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessingError.unreadable
        }
        let output = mode == .keep ? image : try removeBackground(image, floodFromEdges: mode == .smart)
        return try encodePNG(output)
    }

    // MARK: - Background removal

    private static func removeBackground(_ image: CGImage, floodFromEdges: Bool) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw ImageProcessingError.unreadable }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let result: CGImage? = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = raw.bindMemory(to: UInt8.self)
            clearBackground(buffer, width: width, height: height, floodFromEdges: floodFromEdges)
            guard let full = context.makeImage() else { return nil }
            if let crop = opaqueBounds(buffer, width: width, height: height), let cropped = full.cropping(to: crop) {
                return cropped
            }
            return full
        }
        guard let result else { throw ImageProcessingError.encodingFailed }
        return result
    }

    private static func whiteness(_ p: UnsafeMutableBufferPointer<UInt8>, _ offset: Int) -> Int {
        let alpha = Int(p[offset + 3])
        if alpha == 0 { return 255 }
        let minChannel = min(Int(p[offset]), Int(p[offset + 1]), Int(p[offset + 2]))
        return min(255, minChannel * 255 / alpha)
    }

    private static func fade(_ p: UnsafeMutableBufferPointer<UInt8>, _ offset: Int, whiteness value: Int) {
        guard value >= softThreshold else { return }
        let factor = value >= solidThreshold
            ? 0
            : (solidThreshold - value) * 255 / (solidThreshold - softThreshold)
        for channel in 0..<4 {
            p[offset + channel] = UInt8(Int(p[offset + channel]) * factor / 255)
        }
    }

    private static func clearBackground(_ p: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, floodFromEdges: Bool) {
        let count = width * height
        var values = [Int](repeating: 0, count: count)
        for index in 0..<count {
            values[index] = whiteness(p, index * 4)
        }

        guard floodFromEdges else {
            for index in 0..<count { fade(p, index * 4, whiteness: values[index]) }
            return
        }

        // Flood fill from the borders: only light pixels connected to the edge are background,
        // so white areas *inside* the logo are preserved.
        var visited = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        stack.reserveCapacity(count / 4)

        func seed(_ index: Int) {
            if !visited[index] && values[index] >= softThreshold {
                visited[index] = true
                stack.append(index)
            }
        }

        for x in 0..<width {
            seed(x)
            seed((height - 1) * width + x)
        }
        for y in 0..<height {
            seed(y * width)
            seed(y * width + width - 1)
        }
        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            if x > 0 { seed(index - 1) }
            if x < width - 1 { seed(index + 1) }
            if y > 0 { seed(index - width) }
            if y < height - 1 { seed(index + width) }
        }
        for index in 0..<count where visited[index] {
            fade(p, index * 4, whiteness: values[index])
        }
    }

    private static func opaqueBounds(_ p: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where p[row + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 2
        let x0 = max(0, minX - pad)
        let y0 = max(0, minY - pad)
        let x1 = min(width, maxX + pad + 1)
        let y1 = min(height, maxY + pad + 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.encodingFailed }
        return data as Data
    }
}
