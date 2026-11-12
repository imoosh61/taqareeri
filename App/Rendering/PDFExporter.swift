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

    private static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "تقرير" : String(cleaned.prefix(80))
    }
}
