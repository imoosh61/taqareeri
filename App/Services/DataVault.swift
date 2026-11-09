import CryptoKit
import Foundation
import Security

enum VaultError: LocalizedError {
    case keyUnavailable
    case corrupted

    var errorDescription: String? {
        switch self {
        case .keyUnavailable: return "مفتاح التشفير غير متاح حالياً. افتح قفل الجهاز وحاول مرة أخرى."
        case .corrupted: return "الملف تالف أو لا يمكن فك تشفيره."
        }
    }
}

/// Private, encrypted storage for reports and templates.
/// - Lives in Application Support (not visible in the Files app or when the phone is connected to a computer).
/// - Every file is sealed with AES-256-GCM; the key is generated on first use and kept in the Keychain.
/// - The key is backup-migratable (not "this device only") so an encrypted iCloud/computer backup restores intact.
enum DataVault {
    private static let magic = Data("TQR1".utf8)
    private static let keyAccount = "vault.aes256.key"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    static let baseURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutable = url
        try? mutable.setResourceValues(values)
        return url
    }()

    static func directory(_ name: String) -> URL {
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Key

    private static func key() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }

        switch KeychainStore.readData(for: keyAccount) {
        case .found(let data) where data.count == 32:
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        case .notFound:
            let key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            guard KeychainStore.setData(data, for: keyAccount, accessible: kSecAttrAccessibleAfterFirstUnlock) else {
                throw VaultError.keyUnavailable
            }
            cachedKey = key
            return key
        default:
            // Keychain locked or unreadable: never generate a new key here, or existing data would be lost.
            throw VaultError.keyUnavailable
        }
    }

    // MARK: - Sealing

    static func isSealed(_ data: Data) -> Bool { data.starts(with: magic) }

    static func seal(_ plain: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key())
        guard let combined = box.combined else { throw VaultError.corrupted }
        return magic + combined
    }

    /// Opens sealed data; plain (pre-encryption) files are returned as they are.
    static func open(_ data: Data) throws -> Data {
        guard isSealed(data) else { return data }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
            return try AES.GCM.open(box, using: key())
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.corrupted
        }
    }

    static func write(_ plain: Data, to url: URL) throws {
        try seal(plain).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read(_ url: URL) throws -> Data {
        try open(Data(contentsOf: url))
    }

    // MARK: - Migration from version 1.0.x (plain files in Documents)

    /// Moves the old Documents/Reports, Documents/templates.json and Documents/Fonts into the vault,
    /// encrypting reports and templates. Safe to call on every launch.
    static func migrateLegacyDocuments() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let oldReports = documents.appendingPathComponent("Reports", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(at: oldReports, includingPropertiesForKeys: nil) {
            let target = directory("Reports")
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file) else { continue }
                let destination = target.appendingPathComponent(file.deletingPathExtension().lastPathComponent).appendingPathExtension("tqr")
                if (try? write(data, to: destination)) != nil {
                    try? fileManager.removeItem(at: file)
                }
            }
            removeIfEmpty(oldReports)
        }

        let oldTemplates = documents.appendingPathComponent("templates.json")
        if let data = try? Data(contentsOf: oldTemplates) {
            if (try? write(data, to: baseURL.appendingPathComponent("templates.tqr"))) != nil {
                try? fileManager.removeItem(at: oldTemplates)
            }
        }

        let oldFonts = documents.appendingPathComponent("Fonts", isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(at: oldFonts, includingPropertiesForKeys: nil) {
            let target = directory("Fonts")
            for file in files {
                try? fileManager.moveItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
            }
            removeIfEmpty(oldFonts)
        }
    }

    private static func removeIfEmpty(_ url: URL) {
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: url.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Temporary files (exported PDFs, backups) are removed as soon as they have been shared.
enum TempFiles {
    static var exportsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    static func cleanup() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: exportsFolder)
        let temp = fileManager.temporaryDirectory
        let files = (try? fileManager.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["tqrbackup", "json", "pdf"].contains(file.pathExtension) {
            try? fileManager.removeItem(at: file)
        }
    }
}
