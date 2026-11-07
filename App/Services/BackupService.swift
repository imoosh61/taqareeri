import Foundation

/// A single-file backup of all drafts and templates. Saving it to iCloud Drive (via the share sheet
/// or Files) gives cloud backup without requiring iCloud entitlements, which sideloaded apps lack.
struct BackupBundle: Codable {
    var version = 1
    var createdAt = Date()
    var reports: [Report]
    var templates: [HeaderTemplate]
}

enum BackupError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        "ملف النسخة الاحتياطية من إصدار غير مدعوم."
    }
}

enum BackupService {
    static func makeBackupFile(reports: [Report], templates: [HeaderTemplate]) throws -> URL {
        let bundle = BackupBundle(reports: reports, templates: templates)
        let data = try JSONEncoder().encode(bundle)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "Taqareeri-Backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func readBackup(from url: URL) throws -> BackupBundle {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bundle = try JSONDecoder().decode(BackupBundle.self, from: Data(contentsOf: url))
        guard bundle.version <= 1 else { throw BackupError.unsupportedVersion }
        return bundle
    }
}
