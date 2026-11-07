import Foundation

enum FrameCategory: String, CaseIterable, Identifiable {
    case all, official, geometric, islamic, calm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "الكل"
        case .official: return "رسمي"
        case .geometric: return "هندسي"
        case .islamic: return "إسلامي"
        case .calm: return "هادئ"
        }
    }
}

enum FrameStyle: String, Codable, CaseIterable, Identifiable {
    case none, single, double, thickThin, cornerAccents, geometric, islamic, calm, dotted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "بدون إطار"
        case .single: return "خط بسيط"
        case .double: return "خط مزدوج"
        case .thickThin: return "سميك ورفيع"
        case .cornerAccents: return "زوايا رسمية"
        case .geometric: return "معيّنات"
        case .islamic: return "نجوم إسلامية"
        case .calm: return "حواف دائرية"
        case .dotted: return "منقّط أنيق"
        }
    }

    var category: FrameCategory {
        switch self {
        case .none: return .all
        case .single, .double, .thickThin, .cornerAccents: return .official
        case .geometric: return .geometric
        case .islamic: return .islamic
        case .calm, .dotted: return .calm
        }
    }
}
