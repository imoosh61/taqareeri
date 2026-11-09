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

/// Evidence block ("الشواهد") that can be placed and sized freely on a page.
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
