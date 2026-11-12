import CoreGraphics
import Foundation

/// One evidence item: a photo or a QR code (e.g. a link to a folder of photos).
struct EvidenceItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case photo, qr
    }

    var id = UUID()
    var kind: Kind
    /// JPEG data for photos.
    var imageData: Data?
    /// Link or text encoded in the QR code.
    var qrText = ""
    var caption = ""
}

/// One evidence box ("الشواهد") on one page: up to four photos / QR codes, placed and sized freely.
/// A report can hold any number of boxes (e.g. one per page).
struct EvidenceBlock: Identifiable, Codable, Equatable {
    static let maxItems = 4

    var id = UUID()
    var title = "الشواهد"
    var items: [EvidenceItem] = []
    var showBorder = true
    /// Crop photos to fill their cells (otherwise fit whole photo).
    var fillCells = true
    /// Body page index (0 = first page).
    var page = 0
    /// Position & size in A4 points; nil = automatic.
    var rect: CGRect?

    var isVisible: Bool { !items.isEmpty }
    var canAddItems: Bool { items.count < Self.maxItems }
}

/// Single evidence box as saved by version 1.1 (read only, converted to `EvidenceBlock`).
struct EvidenceSettings: Codable, Equatable {
    static let maxItems = 4

    var isEnabled = false
    var title = "الشواهد"
    var items: [EvidenceItem] = []
    var showBorder = true
    /// Crop photos to fill their cells (otherwise fit whole photo).
    var fillCells = true
    /// Body page index (text reports). Form reports always use the first page.
    var pageIndex = 0
    /// Position & size in A4 points; nil = automatic.
    var customRect: CGRect?

    var isVisible: Bool { isEnabled && !items.isEmpty }
}
