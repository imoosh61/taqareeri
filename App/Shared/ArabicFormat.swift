import Foundation

/// Locale-aware Arabic formatting for numbers, Hijri/Gregorian dates and page labels.
enum ArabicFormat {
    static func locale(_ numerals: NumeralStyle) -> Locale {
        Locale(identifier: numerals == .arabicIndic ? "ar_SA@numbers=arab" : "ar_SA@numbers=latn")
    }

    static func number(_ value: Int, _ numerals: NumeralStyle) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale(numerals)
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func dateFormatter(_ calendar: Calendar.Identifier, _ format: String, _ numerals: NumeralStyle) -> DateFormatter {
        let formatter = DateFormatter()
        var cal = Calendar(identifier: calendar)
        cal.locale = locale(numerals)
        formatter.calendar = cal
        formatter.locale = locale(numerals)
        formatter.dateFormat = format
        return formatter
    }

    static func hijri(_ date: Date, _ numerals: NumeralStyle) -> String {
        dateFormatter(.islamicUmmAlQura, "yyyy/MM/dd", numerals).string(from: date) + " هـ"
    }

    static func gregorian(_ date: Date, _ numerals: NumeralStyle) -> String {
        dateFormatter(.gregorian, "yyyy/MM/dd", numerals).string(from: date) + " م"
    }

    static func dayName(_ date: Date) -> String {
        dateFormatter(.gregorian, "EEEE", .arabicIndic).string(from: date)
    }

    /// Lines for the left (documentation & time) block of the header.
    static func headerDateLines(_ header: HeaderInfo, numerals: NumeralStyle) -> [String] {
        var lines: [String] = []
        if header.showDayName {
            lines.append("اليوم: " + dayName(header.date))
        }
        switch header.dateMode {
        case .hijri:
            lines.append("التاريخ: " + hijri(header.date, numerals))
        case .gregorian:
            lines.append("التاريخ: " + gregorian(header.date, numerals))
        case .both:
            lines.append("التاريخ: " + hijri(header.date, numerals))
            lines.append("الموافق: " + gregorian(header.date, numerals))
        }
        if !header.referenceNumber.trimmed.isEmpty {
            lines.append("الرقم: " + header.referenceNumber.trimmed)
        }
        if !header.attachments.trimmed.isEmpty {
            lines.append("المرفقات: " + header.attachments.trimmed)
        }
        return lines
    }

    static func coverDateLines(_ header: HeaderInfo, numerals: NumeralStyle) -> [String] {
        switch header.dateMode {
        case .hijri: return [hijri(header.date, numerals)]
        case .gregorian: return [gregorian(header.date, numerals)]
        case .both: return [hijri(header.date, numerals) + "  —  " + gregorian(header.date, numerals)]
        }
    }

    static func pageLabel(_ page: Int, of total: Int, _ numerals: NumeralStyle) -> String {
        "صفحة \(number(page, numerals)) من \(number(total, numerals))"
    }
}
