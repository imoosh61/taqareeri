import SwiftUI
import UIKit

/// App identity & credits.
enum AppInfo {
    static let developer = "Mohammad Hakami - imoosh"
    static let developerArabic = "محمد حكمي"
    static let copyright = "© \(Calendar(identifier: .gregorian).component(.year, from: Date())) Mohammad Hakami - imoosh. جميع الحقوق محفوظة."
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

enum Theme {
    /// Defaults; the live, user-chosen colours come from `ThemeStore`.
    static let accentHex = "1F3A5F"
    static let goldHex = "B08D57"
}

extension UIColor {
    convenience init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        let value = (cleaned.count == 6 ? UInt64(cleaned, radix: 16) : nil) ?? 0x1F3A5F
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return Theme.accentHex }
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIFont {
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.traitBold) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum Geometry {
    /// Largest rect with the image's aspect ratio that fits inside `box`, centered.
    static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: box.midX - fitted.width / 2,
            y: box.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

/// Wraps a value so it can drive `.sheet(item:)`.
struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct PageRef: Identifiable, Hashable {
    let id: Int
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Checkerboard used behind transparent images (logo, stamp, signature) to show removed background.
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color.gray.opacity(0.18)))
                }
            }
        }
        .background(Color.white)
    }
}

/// Shows a stored PNG over a checkerboard, or a placeholder.
struct TransparentImagePreview: View {
    let data: Data?
    let placeholder: String

    var body: some View {
        ZStack {
            CheckerboardBackground()
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text(placeholder)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
    }
}

enum KeyboardHelper {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
