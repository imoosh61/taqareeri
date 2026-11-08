import Foundation
import UIKit

// MARK: - Enumerations

enum DateMode: String, Codable, CaseIterable, Identifiable {
    case hijri, gregorian, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hijri: return "هجري"
        case .gregorian: return "ميلادي"
        case .both: return "هجري وميلادي"
        }
    }
}

enum HeaderPlacement: String, Codable, CaseIterable, Identifiable {
    case firstPage, allPages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstPage: return "الصفحة الأولى فقط"
        case .allPages: return "كل الصفحات"
        }
    }
}

enum NumeralStyle: String, Codable, CaseIterable, Identifiable {
    case arabicIndic, western
    var id: String { rawValue }
    var title: String {
        switch self {
        case .arabicIndic: return "٠١٢٣"
        case .western: return "0123"
        }
    }
}

enum ParagraphAlignment: String, Codable, CaseIterable, Identifiable {
    case right, center, justified, left
    var id: String { rawValue }

    var title: String {
        switch self {
        case .right: return "يمين"
        case .center: return "وسط"
        case .justified: return "ضبط"
        case .left: return "يسار"
        }
    }

    var systemImage: String {
        switch self {
        case .right: return "text.alignright"
        case .center: return "text.aligncenter"
        case .justified: return "text.justify"
        case .left: return "text.alignleft"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .right: return .right
        case .center: return .center
        case .justified: return .justified
        case .left: return .left
        }
    }

    init(nsAlignment: NSTextAlignment) {
        switch nsAlignment {
        case .center: self = .center
        case .justified: self = .justified
        case .left: self = .left
        default: self = .right
        }
    }
}

// MARK: - Report sections

struct HeaderInfo: Codable, Equatable {
    var isEnabled = true
    var placement: HeaderPlacement = .firstPage
    var topLine = "المملكة العربية السعودية"
    var ministry = ""
    var generalAdministration = ""
    var department = ""
    var logoPNG: Data?
    var date = Date()
    var dateMode: DateMode = .both
    var showDayName = true
    var referenceNumber = ""
    var attachments = ""
    // Optional so older saved reports (without these keys) still decode.
    var adminFontSizeValue: Double?
    var dateFontSizeValue: Double?
    var adminOffsetValue: Double?
    var dateOffsetValue: Double?
    var adminAlignmentValue: ParagraphAlignment?
    var dateAlignmentValue: ParagraphAlignment?

    /// Horizontal shift of each header block in points (+ = right, − = left).
    var adminOffset: Double {
        get { adminOffsetValue ?? 0 }
        set { adminOffsetValue = newValue == 0 ? nil : newValue }
    }

    var dateOffset: Double {
        get { dateOffsetValue ?? 0 }
        set { dateOffsetValue = newValue == 0 ? nil : newValue }
    }

    var adminAlignment: ParagraphAlignment {
        get { adminAlignmentValue ?? .center }
        set { adminAlignmentValue = newValue }
    }

    var dateAlignment: ParagraphAlignment {
        get { dateAlignmentValue ?? .right }
        set { dateAlignmentValue = newValue }
    }

    static let defaultAdminFontSize = 12.5
    static let defaultDateFontSize = 11.5

    var adminFontSize: Double {
        get { adminFontSizeValue ?? Self.defaultAdminFontSize }
        set { adminFontSizeValue = newValue }
    }

    var dateFontSize: Double {
        get { dateFontSizeValue ?? Self.defaultDateFontSize }
        set { dateFontSizeValue = newValue }
    }
}

/// Line spacing like Microsoft Word: a fixed line height of 1.2 × font size × multiple,
/// so the number of lines per page depends only on the font size (as on a computer).
enum LineSpacing: String, Codable, CaseIterable, Identifiable {
    case single, onePointFifteen, onePointFive, double, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "مفرد (مثل Word)"
        case .onePointFifteen: return "1.15"
        case .onePointFive: return "1.5"
        case .double: return "مزدوج"
        case .custom: return "مخصص"
        }
    }

    /// nil = custom (natural font line height × `lineHeightMultiple`).
    var multiple: Double? {
        switch self {
        case .single: return 1.0
        case .onePointFifteen: return 1.15
        case .onePointFive: return 1.5
        case .double: return 2.0
        case .custom: return nil
        }
    }

    static let wordLineFactor = 1.2
}

struct TextStyleSettings: Codable, Equatable {
    var fontName = FontCatalog.defaultFontName
    var fontSize: Double = 16
    var lineHeightMultiple: Double = 1.35
    var paragraphSpacing: Double = 6
    var defaultAlignment: ParagraphAlignment = .justified
    /// New reports use Word-like single spacing; older saved reports decode as nil (custom).
    var lineSpacingValue: LineSpacing? = .single

    var lineSpacing: LineSpacing {
        get { lineSpacingValue ?? .custom }
        set { lineSpacingValue = newValue }
    }

    /// Fixed line height in points, or nil for natural spacing.
    func fixedLineHeight(forFontSize size: Double) -> CGFloat? {
        guard let multiple = lineSpacing.multiple else { return nil }
        return CGFloat(size * LineSpacing.wordLineFactor * multiple)
    }
}

/// Page margins in points (72 pt = 2.54 cm, Word's "Normal").
enum PageMargins: String, Codable, CaseIterable, Identifiable {
    case normal, moderate, narrow, wide, compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "عادي ٢٫٥٤ سم (مثل Word)"
        case .moderate: return "متوسط"
        case .narrow: return "ضيق ١٫٢٧ سم"
        case .wide: return "عريض"
        case .compact: return "مدمج (الإصدار السابق)"
        }
    }

    var horizontal: CGFloat {
        switch self {
        case .normal: return 72
        case .moderate: return 54
        case .narrow: return 36
        case .wide: return 108
        case .compact: return 56
        }
    }

    var top: CGFloat {
        switch self {
        case .narrow: return 36
        case .compact: return 46
        default: return 72
        }
    }

    var bottom: CGFloat { top }
}

struct PageSettings: Codable, Equatable {
    var showPageNumbers = true
    var numerals: NumeralStyle = .arabicIndic
    /// New reports use Word margins; older saved reports decode as nil (previous compact layout).
    var marginsValue: PageMargins? = .normal

    var margins: PageMargins {
        get { marginsValue ?? .compact }
        set { marginsValue = newValue }
    }
}

struct FrameSettings: Codable, Equatable {
    var style: FrameStyle = .double
    var colorHex = "1F3A5F"
    var applyToCover = true
    /// User-imported frame artwork, used when `style == .customImage`.
    var customFramePNG: Data?
}

struct CoverSettings: Codable, Equatable {
    var isEnabled = false
    var subtitle = ""
    var preparedBy = ""
}

struct Employee: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Line printed above the name (e.g. "اسم الموظف" or a job title).
    var label = "اسم الموظف"
    var name = ""
    var signaturePNG: Data?
    /// Free-placement offset from the automatic position, in A4 points (nil = automatic).
    var offsetX: Double?
    var offsetY: Double?

    var offset: CGSize {
        get { CGSize(width: offsetX ?? 0, height: offsetY ?? 0) }
        set {
            offsetX = newValue.width == 0 ? nil : Double(newValue.width)
            offsetY = newValue.height == 0 ? nil : Double(newValue.height)
        }
    }
}

/// Names & signatures block on the last page.
/// One employee → centered; several → right and left, two per row.
struct FooterSettings: Codable, Equatable {
    var showSignatureBlock = false
    var employees: [Employee] = []
    var stampPNG: Data?
    /// Free-placement offset of the stamp, in A4 points.
    var stampOffset: CGSize = .zero

    var hasCustomPositions: Bool {
        stampOffset != .zero || employees.contains { $0.offset != .zero }
    }

    mutating func resetPositions() {
        stampOffset = .zero
        for index in employees.indices { employees[index].offset = .zero }
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showSignatureBlock, employees, stampPNG, stampOffsetX, stampOffsetY
        // Version 1.0 fields (single signer), migrated on load.
        case signerTitle, signerName, signaturePNG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showSignatureBlock = try container.decodeIfPresent(Bool.self, forKey: .showSignatureBlock) ?? false
        stampPNG = try container.decodeIfPresent(Data.self, forKey: .stampPNG)
        stampOffset = CGSize(
            width: try container.decodeIfPresent(Double.self, forKey: .stampOffsetX) ?? 0,
            height: try container.decodeIfPresent(Double.self, forKey: .stampOffsetY) ?? 0
        )
        if let employees = try container.decodeIfPresent([Employee].self, forKey: .employees) {
            self.employees = employees
        } else {
            let title = try container.decodeIfPresent(String.self, forKey: .signerTitle) ?? ""
            let name = try container.decodeIfPresent(String.self, forKey: .signerName) ?? ""
            let signature = try container.decodeIfPresent(Data.self, forKey: .signaturePNG)
            if !title.trimmed.isEmpty || !name.trimmed.isEmpty || signature != nil {
                employees = [Employee(label: title.trimmed.isEmpty ? "اسم الموظف" : title, name: name, signaturePNG: signature)]
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showSignatureBlock, forKey: .showSignatureBlock)
        try container.encode(employees, forKey: .employees)
        try container.encodeIfPresent(stampPNG, forKey: .stampPNG)
        if stampOffset != .zero {
            try container.encode(Double(stampOffset.width), forKey: .stampOffsetX)
            try container.encode(Double(stampOffset.height), forKey: .stampOffsetY)
        }
    }
}

/// Optional opening block addressed to a recipient, e.g.
///   سعادة مدير إدارة المساجد بالحرث
///   الأستاذ/ فلان الفلاني ………………… حفظه الله
///   السلام عليكم ورحمة الله وبركاته، وبعد:
struct AddresseeSettings: Codable, Equatable {
    var isEnabled = false
    var recipientTitle = ""
    var recipientName = ""
    var showHonorific = true
    var honorific = "حفظه الله"
    var showGreeting = true
    var greeting = "السلام عليكم ورحمة الله وبركاته، وبعد:"

    static let honorificSuggestions = ["حفظه الله", "حفظها الله", "وفقه الله", "وفقها الله", "سلمه الله", "المحترم", "المحترمة"]
}

// MARK: - Report

struct Report: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "تقرير جديد"
    var createdAt = Date()
    var updatedAt = Date()
    var header = HeaderInfo()
    var textStyle = TextStyleSettings()
    var page = PageSettings()
    var frame = FrameSettings()
    var cover = CoverSettings()
    var footer = FooterSettings()
    var body = BodyDocument()
    /// Optional so reports saved by earlier versions (without this key) still decode.
    var addresseeStorage: AddresseeSettings?
    var autoFormatStorage: Bool?

    /// Tidy spaces & punctuation automatically before preview and export.
    var autoFormat: Bool {
        get { autoFormatStorage ?? true }
        set { autoFormatStorage = newValue }
    }

    var addressee: AddresseeSettings {
        get { addresseeStorage ?? AddresseeSettings() }
        set { addresseeStorage = newValue }
    }
}

// MARK: - Header template

struct HeaderTemplate: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var header: HeaderInfo
    var frame: FrameSettings
    var createdAt = Date()
}
