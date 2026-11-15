import Darwin
import Foundation
import MachO

/// Runtime integrity checks: jailbreak, attached debugger and injected hooking libraries.
///
/// These checks raise the bar for casual tampering only; a determined attacker can bypass them.
/// The real protection of reports is the encryption in `DataVault` (key in the Keychain).
enum AppGuard {
    struct Findings: Equatable {
        var jailbroken = false
        var debugged = false
        var injected = false

        var isSafe: Bool { !jailbroken && !debugged && !injected }

        /// Arabic description of what was found.
        var reasons: [String] {
            var list: [String] = []
            if jailbroken { list.append("الجهاز مكسور الحماية (Jailbreak)") }
            if debugged { list.append("أداة تصحيح متصلة بالتطبيق") }
            if injected { list.append("مكتبات حقن أو تعديل داخل التطبيق") }
            return list
        }
    }

    /// Runs all checks once. Development builds always report safe (Xcode attaches a debugger).
    static func check() -> Findings {
        #if DEBUG || targetEnvironment(simulator)
        return Findings()
        #else
        return Findings(jailbroken: isJailbroken(), debugged: isDebugged(), injected: hasInjectedLibraries())
        #endif
    }

    static func isSafe() -> Bool { check().isSafe }

    // MARK: 1) Jailbreak

    private static let suspiciousPaths = [
        // Classic (rootful) jailbreaks
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/etc/apt",
        "/private/var/lib/apt/",
        // Rootless jailbreaks (Dopamine, palera1n…) live under /var/jb
        "/var/jb",
        "/private/preboot/jb",
        "/var/binpack"
    ]

    static func isJailbroken() -> Bool {
        let fileManager = FileManager.default
        if suspiciousPaths.contains(where: { fileManager.fileExists(atPath: $0) }) {
            return true
        }
        // Writing outside the sandbox is impossible on a normal device. A unique name avoids
        // touching any real file, and the test file is always removed.
        let probe = "/private/" + UUID().uuidString + ".txt"
        do {
            try "x".write(toFile: probe, atomically: false, encoding: .utf8)
            try? fileManager.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
    }

    // MARK: 2) Debugger

    static func isDebugged() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: 3) Injected libraries

    private static let suspiciousLibraries = [
        "frida", "cycript", "substrate", "substitute", "libhooker", "ellekit",
        "tweakinject", "sslkillswitch", "revealserver"
    ]

    static func hasInjectedLibraries() -> Bool {
        if let inserted = getenv("DYLD_INSERT_LIBRARIES"), strlen(inserted) > 0 {
            return true
        }
        let count = _dyld_image_count()
        for index in 0..<count {
            guard let name = _dyld_get_image_name(index) else { continue }
            // Only the file name: avoids matching folder names of system frameworks.
            let file = (String(cString: name) as NSString).lastPathComponent.lowercased()
            if suspiciousLibraries.contains(where: { file.contains($0) }) {
                return true
            }
        }
        return false
    }
}

/// Holds the result for the session and the user's choice (warn only / block).
@MainActor
final class GuardState: ObservableObject {
    static let strictKey = "security.strictMode"

    @Published private(set) var result = AppGuard.Findings()
    @Published var acknowledged = false

    init() {
        result = AppGuard.check()
    }

    var isStrict: Bool { UserDefaults.standard.bool(forKey: Self.strictKey) }

    /// Re-checks when the app returns to the foreground (a debugger can be attached later).
    func recheck() {
        let fresh = AppGuard.check()
        if fresh != result {
            result = fresh
            acknowledged = false
        }
    }

    var showsWarning: Bool { !result.isSafe && (isStrict || !acknowledged) }
}
