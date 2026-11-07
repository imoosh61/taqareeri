import Foundation

enum FontCategory: Int, CaseIterable, Identifiable, Comparable {
    case naskh, modern, kufi, calligraphic, display, system, imported

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .naskh: return "نسخ وخطوط تقليدية"
        case .modern: return "خطوط حديثة"
        case .kufi: return "كوفي"
        case .calligraphic: return "رقعة وخطوط يدوية"
        case .display: return "خطوط عناوين وزخرفية"
        case .system: return "خطوط النظام"
        case .imported: return "خطوط مستوردة"
        }
    }

    static func < (lhs: FontCategory, rhs: FontCategory) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ReportFont: Identifiable, Hashable {
    let postScriptName: String
    let displayName: String
    let category: FontCategory
    let isImported: Bool
    var id: String { postScriptName }
}

enum FontCatalog {
    static let defaultFontName = "Amiri-Regular"

    /// Arabic display names and categories keyed by font family name.
    /// Fonts are discovered from the bundle at runtime, so this only labels them.
    /// "Traditional Arabic" is proprietary (Microsoft) and cannot be bundled;
    /// Scheherazade New is its closest open equivalent, and users can import a licensed copy.
    static let families: [String: (name: String, category: FontCategory)] = [
        "Amiri": ("أميري", .naskh),
        "Scheherazade New": ("شهرزاد — بديل Traditional Arabic", .naskh),
        "Noto Naskh Arabic": ("نوتو نسخ", .naskh),
        "Lateef": ("لطيف", .naskh),
        "Harmattan": ("هرمتان", .naskh),
        "Markazi Text": ("مركزي", .naskh),
        "Mirza": ("ميرزا", .naskh),
        "Tajawal": ("تجوال", .modern),
        "Almarai": ("المراعي", .modern),
        "Cairo": ("القاهرة", .modern),
        "IBM Plex Sans Arabic": ("آي بي إم بلكس عربي", .modern),
        "Noto Sans Arabic": ("نوتو سانس", .modern),
        "Readex Pro": ("ريدكس برو", .modern),
        "Vazirmatn": ("وزير متن", .modern),
        "Changa": ("تشانغا", .modern),
        "Baloo Bhaijaan 2": ("بالو", .modern),
        "Noto Kufi Arabic": ("نوتو كوفي", .kufi),
        "Reem Kufi": ("ريم كوفي", .kufi),
        "Kufam": ("كوفام", .kufi),
        "Qahiri": ("قاهري", .kufi),
        "Aref Ruqaa": ("عارف رقعة", .calligraphic),
        "Alkalami": ("القلمي", .calligraphic),
        "Katibeh": ("كاتبة", .calligraphic),
        "El Messiri": ("المسيري", .display),
        "Lalezar": ("لاله‌زار", .display),
        "Rakkas": ("رقّاص", .display),
        "Marhey": ("مرحي", .display),
        "Lemonada": ("ليمونادة", .display),
        "Geeza Pro": ("جيزة", .system),
        "Damascus": ("دمشق", .system),
        "Al Nile": ("النيل", .system),
        "Baghdad": ("بغداد", .system),
        "Diwan Mishafi": ("ديواني مصحفي", .system),
        "Farah": ("فرح", .system),
        "Mishafi": ("مصحفي", .system),
        "Kufi Standard GK": ("كوفي قياسي", .system)
    ]

    /// iOS system Arabic fonts (only those present on the device are listed).
    static let systemPostScriptNames = [
        "GeezaPro", "Damascus", "AlNile", "Baghdad", "DiwanMishafi", "Farah", "Mishafi", "KufiStandardGK"
    ]
}
