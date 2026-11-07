import SwiftUI

@main
struct OfficialReportsApp: App {
    @StateObject private var reportStore = ReportStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var fontRegistry = FontRegistry()
    @StateObject private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
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
