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
    static func export(_ render: PageRenderContext) throws -> URL {
        let pageCount = render.pagination.totalPages
        guard pageCount > 0 else { throw PDFExportError.emptyDocument }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: render.report.title,
            kCGPDFContextCreator as String: "تقاريري — \(AppInfo.developer)"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: A4.bounds, format: format)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: render.report.title)).appendingPathExtension("pdf")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try renderer.writePDF(to: url) { context in
            for page in 0..<pageCount {
                context.beginPage()
                PageRenderer.draw(page: page, context: render, in: context.cgContext)
            }
        }
        return url
    }

    private static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "تقرير" : String(cleaned.prefix(80))
    }
}
