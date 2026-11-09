import SwiftUI

@main
struct OfficialReportsApp: App {
    @StateObject private var reportStore = ReportStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var fontRegistry = FontRegistry()
    @StateObject private var theme = ThemeStore()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TempFiles.cleanup()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if lock.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                } else if scenePhase != .active {
                    PrivacyCoverView()
                }
            }
                .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { lock.lockIfNeeded() }
                }
                .environmentObject(lock)
                .environmentObject(reportStore)
                .environmentObject(templateStore)
                .environmentObject(fontRegistry)
                .environmentObject(theme)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .tint(theme.accent)
                .preferredColorScheme(theme.appearance.colorScheme)
        }
    }
}
