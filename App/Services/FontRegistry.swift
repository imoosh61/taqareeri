import CoreText
import UIKit

enum FontImportError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "الملف ليس خطاً صالحاً (TTF أو OTF)."
    }
}

/// Discovers every font bundled with the app (downloaded at build time), the iOS system Arabic
/// fonts, and fonts imported by the user (e.g. a licensed "Traditional Arabic").
/// One entry per family (its regular face); bold is resolved when text is styled.
@MainActor
final class FontRegistry: ObservableObject {
    @Published private(set) var fonts: [ReportFont] = []
    @Published var errorMessage: String?

    private let folder: URL
    private var imported: [String: URL] = [:]   // postScriptName → file
    private var importedFonts: [ReportFont] = []
    private var bundledFonts: [ReportFont] = []

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        bundledFonts = Self.discoverBundledFonts()
        registerImportedFonts()
        refresh()
    }

    /// Fonts grouped for pickers, in category order.
    var grouped: [(category: FontCategory, fonts: [ReportFont])] {
        let groups = Dictionary(grouping: fonts, by: \.category)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
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

        guard let font = registerImported(destination) else {
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

    // MARK: - Discovery

    private func refresh() {
        var families = Set(bundledFonts.compactMap { UIFont(name: $0.postScriptName, size: 12)?.familyName })
        var system: [ReportFont] = []
        for name in FontCatalog.systemPostScriptNames {
            guard let font = UIFont(name: name, size: 12), families.insert(font.familyName).inserted else { continue }
            system.append(Self.entry(postScriptName: name, family: font.familyName, fallbackCategory: .system))
        }
        fonts = (bundledFonts + system).sorted {
            $0.category == $1.category ? $0.displayName < $1.displayName : $0.category < $1.category
        } + importedFonts.sorted { $0.displayName < $1.displayName }
    }

    private static func discoverBundledFonts() -> [ReportFont] {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])

        // Register everything first so bold faces resolve by name later.
        var candidates: [(postScriptName: String, url: URL)] = []
        for url in urls {
            guard let postScriptName = postScriptName(of: url) else { continue }
            if UIFont(name: postScriptName, size: 12) == nil {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
            candidates.append((postScriptName, url))
        }

        var seenFamilies = Set<String>()
        var result: [ReportFont] = []
        // Regular faces first, so a family is represented by its regular style.
        let ordered = candidates.filter { $0.postScriptName.hasSuffix("-Regular") }
            + candidates.filter { !$0.postScriptName.hasSuffix("-Regular") }
        for candidate in ordered {
            guard let font = UIFont(name: candidate.postScriptName, size: 12) else { continue }
            if font.isBold && !candidate.postScriptName.hasSuffix("-Regular") { continue }
            guard seenFamilies.insert(font.familyName).inserted else { continue }
            result.append(entry(postScriptName: candidate.postScriptName, family: font.familyName, fallbackCategory: .modern))
        }
        return result
    }

    private static func entry(postScriptName: String, family: String, fallbackCategory: FontCategory) -> ReportFont {
        if let known = FontCatalog.families[family] {
            return ReportFont(postScriptName: postScriptName, displayName: "\(known.name) — \(family)", category: known.category, isImported: false)
        }
        return ReportFont(postScriptName: postScriptName, displayName: family, category: fallbackCategory, isImported: false)
    }

    private static func postScriptName(of url: URL) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL), let cgFont = CGFont(provider) else { return nil }
        return cgFont.postScriptName as String?
    }

    private func registerImportedFonts() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        importedFonts = files.compactMap { registerImported($0) }
    }

    private func registerImported(_ url: URL) -> ReportFont? {
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
        return ReportFont(postScriptName: postScriptName, displayName: fullName, category: .imported, isImported: true)
    }
}
