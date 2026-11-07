import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "تلقائي"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User-customisable app colours (persisted in UserDefaults).
@MainActor
final class ThemeStore: ObservableObject {
    /// Wide palette offered for the app accent, secondary colour and frame colours.
    static let palette: [String] = [
        "1F3A5F", "2563EB", "0EA5E9", "4F46E5", "7C3AED", "9333EA",
        "0F766E", "14B8A6", "006C35", "1E6B4F", "059669", "65A30D",
        "B08D57", "D97706", "EA580C", "DC2626", "E11D48", "DB2777",
        "7A2335", "800020", "6F4E37", "78350F", "475569", "1C1C1E"
    ]

    @Published var accentHex: String { didSet { save(accentHex, Keys.accent) } }
    @Published var secondaryHex: String { didSet { save(secondaryHex, Keys.secondary) } }
    @Published var appearance: AppAppearance { didSet { save(appearance.rawValue, Keys.appearance) } }

    private enum Keys {
        static let accent = "theme.accent"
        static let secondary = "theme.secondary"
        static let appearance = "theme.appearance"
    }

    init() {
        let defaults = UserDefaults.standard
        accentHex = defaults.string(forKey: Keys.accent) ?? Theme.accentHex
        secondaryHex = defaults.string(forKey: Keys.secondary) ?? Theme.goldHex
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    var accent: Color { Color(hex: accentHex) }
    var secondary: Color { Color(hex: secondaryHex) }
    var accentUIColor: UIColor { UIColor(hex: accentHex) }

    func reset() {
        accentHex = Theme.accentHex
        secondaryHex = Theme.goldHex
        appearance = .system
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
