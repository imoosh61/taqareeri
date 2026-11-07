import CoreText
import UIKit

enum FontImportError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "الملف ليس خطاً صالحاً (TTF أو OTF)."
    }
}

/// Lists the fonts available to reports: bundled/system Arabic fonts that exist on the device,
/// plus fonts imported by the user (e.g. a licensed "Traditional Arabic").
@MainActor
final class FontRegistry: ObservableObject {
    @Published private(set) var fonts: [ReportFont] = []
    @Published var errorMessage: String?

    private let folder: URL
    private var imported: [String: URL] = [:]   // postScriptName → file
    private var importedFonts: [ReportFont] = []

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        registerImportedFonts()
        refresh()
    }

    func displayName(for postScriptName: String) -> String {
        fonts.first { $0.postScriptName == postScriptName }?.displayName ?? postScriptName
    }

    func importFont(from url: URL) throws -> ReportFont {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let destination = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)

        guard let font = register(destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw FontImportError.unreadable
        }
        importedFonts.removeAll { $0.postScriptName == font.postScriptName }
        importedFonts.append(font)
        refresh()
        return font
    }

    func deleteImported(_ font: ReportFont) {
        guard let url = imported[font.postScriptName] else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            errorMessage = "تعذر حذف الخط: \(error.localizedDescription)"
        }
        imported[font.postScriptName] = nil
        importedFonts.removeAll { $0.postScriptName == font.postScriptName }
        refresh()
    }

    private func refresh() {
        let available = FontCatalog.bundled.filter { UIFont(name: $0.postScriptName, size: 12) != nil }
        fonts = available + importedFonts.sorted { $0.displayName < $1.displayName }
    }

    private func registerImportedFonts() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        importedFonts = files.compactMap { register($0) }
    }

    private func register(_ url: URL) -> ReportFont? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String? else {
            return nil
        }
        if UIFont(name: postScriptName, size: 12) == nil {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
        guard UIFont(name: postScriptName, size: 12) != nil else { return nil }
        imported[postScriptName] = url
        let fullName = (cgFont.fullName as String?) ?? postScriptName
        return ReportFont(postScriptName: postScriptName, displayName: fullName + " (مستورد)", isImported: true)
    }
}
