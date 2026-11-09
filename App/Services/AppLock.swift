import LocalAuthentication
import SwiftUI

/// Optional app lock with Face ID / Touch ID, falling back to the device passcode.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published private(set) var isEnabled: Bool
    @Published var message: String?

    private static let enabledKey = "security.appLock"
    private var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// "بصمة الوجه" / "بصمة الإصبع" / "رمز الجوال" depending on the device.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "بصمة الوجه"
        case .touchID: return "بصمة الإصبع"
        case .opticID: return "بصمة العين"
        default: return "رمز الجوال"
        }
    }

    var methodIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "افتح تطبيق تقاريري") {
            isLocked = false
            message = nil
        }
    }

    /// Turning the lock on or off always requires authentication first.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        guard await authenticate(reason: enabled ? "تفعيل قفل التطبيق" : "إيقاف قفل التطبيق") else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        isLocked = false
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "إلغاء"
        context.localizedFallbackTitle = "استخدام رمز الجوال"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "لا يوجد رمز قفل مفعّل على الجهاز. فعّله من الإعدادات أولاً."
            return false
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !success { message = "لم يتم التحقق." }
            return success
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
            return false
        } catch {
            message = "تعذر التحقق: \(error.localizedDescription)"
            return false
        }
    }
}

/// Full-screen lock shown while the app is locked.
struct LockScreenView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.accent, theme.accent.opacity(0.85), theme.secondary.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text("تقاريري")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("التطبيق مقفل")
                    .foregroundStyle(.white.opacity(0.85))
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("فتح بـ \(lock.methodName)", systemImage: lock.methodIcon)
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                        .foregroundStyle(theme.accent)
                }
                if let message = lock.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .task { await lock.unlock() }
    }
}

/// Covers the content in the app switcher so report contents are not visible.
struct PrivacyCoverView: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack {
            theme.accent.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 56))
                Text("تقاريري")
                    .font(.title.weight(.bold))
            }
            .foregroundStyle(.white)
        }
    }
}
