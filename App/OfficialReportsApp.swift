import SwiftUI

@main
struct OfficialReportsApp: App {
    @StateObject private var reportStore = ReportStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var fontRegistry = FontRegistry()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(reportStore)
                .environmentObject(templateStore)
                .environmentObject(fontRegistry)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .tint(Theme.accent)
        }
    }
}
