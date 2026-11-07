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
}

struct TextStyleSettings: Codable, Equatable {
    var fontName = FontCatalog.defaultFontName
    var fontSize: Double = 16
    var lineHeightMultiple: Double = 1.35
    var paragraphSpacing: Double = 8
    var defaultAlignment: ParagraphAlignment = .justified
}

struct PageSettings: Codable, Equatable {
    var showPageNumbers = true
    var numerals: NumeralStyle = .arabicIndic
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
}

/// Names & signatures block on the last page.
/// One employee → centered; several → right and left, two per row.
struct FooterSettings: Codable, Equatable {
    var showSignatureBlock = false
    var employees: [Employee] = []
    var stampPNG: Data?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showSignatureBlock, employees, stampPNG
        // Version 1.0 fields (single signer), migrated on load.
        case signerTitle, signerName, signaturePNG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showSignatureBlock = try container.decodeIfPresent(Bool.self, forKey: .showSignatureBlock) ?? false
        stampPNG = try container.decodeIfPresent(Data.self, forKey: .stampPNG)
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
