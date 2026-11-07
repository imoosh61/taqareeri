import Foundation

enum FrameCategory: String, CaseIterable, Identifiable {
    case all, ornate, official, geometric, islamic, calm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "الكل"
        case .ornate: return "مزخرف"
        case .official: return "رسمي"
        case .geometric: return "هندسي"
        case .islamic: return "إسلامي"
        case .calm: return "هادئ"
        }
    }
}

enum FrameStyle: String, Codable, CaseIterable, Identifiable {
    case none, single, double, thickThin, cornerAccents
    case geometric, najdi
    case islamic, interlace, zellige, arches
    case arabesque, floral, goldCorners, royal
    case calm, dotted
    case customImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "بدون إطار"
        case .single: return "خط بسيط"
        case .double: return "خط مزدوج"
        case .thickThin: return "سميك ورفيع"
        case .cornerAccents: return "زوايا رسمية"
        case .geometric: return "معيّنات"
        case .najdi: return "نجدي"
        case .islamic: return "نجوم إسلامية"
        case .interlace: return "حلقات متشابكة"
        case .zellige: return "فسيفساء"
        case .arches: return "أقواس"
        case .arabesque: return "أرابيسك"
        case .floral: return "توريق نباتي"
        case .goldCorners: return "زوايا ملكية"
        case .royal: return "خرطوشة ملكية"
        case .calm: return "حواف دائرية"
        case .dotted: return "منقّط أنيق"
        case .customImage: return "إطار من صورة"
        }
    }

    var category: FrameCategory {
        switch self {
        case .none, .customImage: return .all
        case .single, .double, .thickThin, .cornerAccents: return .official
        case .geometric, .najdi: return .geometric
        case .islamic, .interlace, .zellige, .arches: return .islamic
        case .arabesque, .floral, .goldCorners, .royal: return .ornate
        case .calm, .dotted: return .calm
        }
    }
}
