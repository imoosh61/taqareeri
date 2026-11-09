import CommonCrypto
import CryptoKit
import Foundation

/// A single-file backup of all reports and templates, encrypted with a password chosen by the user
/// (PBKDF2-SHA256 → AES-256-GCM). It can be kept in iCloud Drive or sent anywhere safely.
struct BackupBundle: Codable {
    var version = 1
    var createdAt = Date()
    var reports: [Report]
    var templates: [HeaderTemplate]
}

enum BackupError: LocalizedError {
    case unsupportedVersion
    case passwordRequired
    case wrongPassword
    case weakPassword
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "ملف النسخة الاحتياطية من إصدار غير مدعوم."
        case .passwordRequired: return "هذه النسخة مشفّرة، أدخل كلمة المرور."
        case .wrongPassword: return "كلمة المرور غير صحيحة أو الملف تالف."
        case .weakPassword: return "كلمة المرور يجب أن تكون ٦ أحرف على الأقل."
        case .keyDerivationFailed: return "تعذر تجهيز التشفير."
        }
    }
}

enum BackupService {
    static let fileExtension = "tqrbackup"
    static let minimumPasswordLength = 6
    private static let magic = Data("TQRB1".utf8)
    private static let iterations: UInt32 = 210_000

    static func isEncrypted(_ data: Data) -> Bool { data.starts(with: magic) }

    static func makeBackupFile(reports: [Report], templates: [HeaderTemplate], password: String) async throws -> URL {
        guard password.count >= minimumPasswordLength else { throw BackupError.weakPassword }
        let bundle = BackupBundle(reports: reports, templates: templates)

        return try await Task.detached(priority: .userInitiated) {
            let plain = try JSONEncoder().encode(bundle)
            var salt = Data(count: 16)
            let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard status == errSecSuccess else { throw BackupError.keyDerivationFailed }

            let key = try deriveKey(password: password, salt: salt, iterations: iterations)
            guard let sealed = try AES.GCM.seal(plain, using: key).combined else { throw BackupError.keyDerivationFailed }

            var header = magic + salt
            var rounds = iterations.bigEndian
            header.append(Data(bytes: &rounds, count: 4))

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let name = "Taqareeri-Backup-\(formatter.string(from: Date())).\(fileExtension)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try (header + sealed).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }.value
    }

    static func readFile(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// Decodes an encrypted backup (password required) or an older unencrypted one.
    static func decode(_ data: Data, password: String?) async throws -> BackupBundle {
        try await Task.detached(priority: .userInitiated) {
            var plain = data
            if isEncrypted(data) {
                guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
                let saltStart = magic.count
                let roundsStart = saltStart + 16
                let bodyStart = roundsStart + 4
                guard data.count > bodyStart else { throw BackupError.wrongPassword }
                let salt = data.subdata(in: saltStart..<roundsStart)
                let rounds = data.subdata(in: roundsStart..<bodyStart).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                let key = try deriveKey(password: password, salt: salt, iterations: rounds)
                do {
                    let box = try AES.GCM.SealedBox(combined: data.subdata(in: bodyStart..<data.count))
                    plain = try AES.GCM.open(box, using: key)
                } catch {
                    throw BackupError.wrongPassword
                }
            }
            let bundle = try JSONDecoder().decode(BackupBundle.self, from: plain)
            guard bundle.version <= 1 else { throw BackupError.unsupportedVersion }
            return bundle
        }.value
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}
