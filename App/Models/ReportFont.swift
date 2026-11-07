import Foundation

struct ReportFont: Identifiable, Hashable {
    let postScriptName: String
    let displayName: String
    let isImported: Bool
    var id: String { postScriptName }
}

enum FontCatalog {
    static let defaultFontName = "Amiri-Regular"

    /// Bundled (downloaded at build time, SIL OFL) and iOS system Arabic fonts.
    /// "Traditional Arabic" is proprietary (Microsoft) and cannot be bundled;
    /// Scheherazade New is its closest open equivalent, and users can import their own licensed copy.
    static let bundled: [ReportFont] = [
        ReportFont(postScriptName: "Amiri-Regular", displayName: "أميري — Amiri", isImported: false),
        ReportFont(postScriptName: "ScheherazadeNew-Regular", displayName: "شهرزاد — بديل Traditional Arabic", isImported: false),
        ReportFont(postScriptName: "Tajawal-Regular", displayName: "تجوال — Tajawal", isImported: false),
        ReportFont(postScriptName: "GeezaPro", displayName: "جيزة — خط النظام", isImported: false),
        ReportFont(postScriptName: "Damascus", displayName: "دمشق — خط النظام", isImported: false),
        ReportFont(postScriptName: "AlNile", displayName: "النيل — خط النظام", isImported: false)
    ]
}
