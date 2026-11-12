import Foundation

/// Sequential outgoing numbers (رقم الصادر) stored on this device.
enum OutgoingNumbering {
    static let enabledKey = "numbering.enabled"
    static let prefixKey = "numbering.prefix"
    static let nextKey = "numbering.next"

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }

    private static var next: Int {
        max(defaults.integer(forKey: nextKey), 1)
    }

    /// The number the next report will get (without consuming it).
    static var preview: String {
        (defaults.string(forKey: prefixKey) ?? "") + String(next)
    }

    /// Returns the next number and advances the counter.
    static func takeNext() -> String {
        let value = preview
        defaults.set(next + 1, forKey: nextKey)
        return value
    }
}
