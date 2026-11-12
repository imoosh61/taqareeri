import UIKit

enum PDFExportError: LocalizedError {
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .emptyDocument: return "لا توجد صفحات لتصديرها."
        }
    }
}

/// Exports all pages into a single vector PDF (text stays selectable and sharp; frames are paths).
@MainActor
enum PDFExporter {
    static func export(_ snapshot: DocumentSnapshot) throws -> URL {
        let pageCount = snapshot.pageCount
        guard pageCount > 0 else { throw PDFExportError.emptyDocument }

        let format = UIGraphicsPDFRendererFormat()
        // Only the report title: no app or developer credits inside shared documents.
        format.documentInfo = [
            kCGPDFContextTitle as String: snapshot.report.title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: A4.bounds, format: format)

        let folder = TempFiles.exportsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: snapshot.report.title)).appendingPathExtension("pdf")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try renderer.writePDF(to: url) { context in
            for page in 0..<pageCount {
                context.beginPage()
                PageRenderer.draw(page: page, snapshot: snapshot, in: context.cgContext)
            }
        }
        return url
    }

    static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "تقرير" : String(cleaned.prefix(80))
    }
}

/// Exports each page as a JPG image (2× A4 points ≈ 1190×1684 px).
@MainActor
enum ImageExporter {
    static func export(_ snapshot: DocumentSnapshot) throws -> [URL] {
        let pageCount = snapshot.pageCount
        guard pageCount > 0 else { throw PDFExportError.emptyDocument }
        let folder = TempFiles.exportsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = PDFExporter.fileName(for: snapshot.report.title)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: A4.size, format: format)
        var urls: [URL] = []
        for page in 0..<pageCount {
            let image = renderer.image { context in
                PageRenderer.draw(page: page, snapshot: snapshot, in: context.cgContext)
            }
            guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
            let name = pageCount == 1 ? base : "\(base) - \(page + 1)"
            let url = folder.appendingPathComponent(name).appendingPathExtension("jpg")
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}
