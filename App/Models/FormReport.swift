import Foundation

/// Text reports (free writing) and form reports (labelled boxes, like teachers' evidence forms)
/// live in separate sections of the app.
enum ReportKind: String, Codable, CaseIterable, Identifiable {
    case text, form

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "التقارير"
        case .form: return "نماذج الشواهد"
        }
    }
}

enum FieldWidth: String, Codable, CaseIterable, Identifiable {
    case full, half, third

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "كامل"
        case .half: return "نصف"
        case .third: return "ثلث"
        }
    }

    var fraction: Double {
        switch self {
        case .full: return 1
        case .half: return 0.5
        case .third: return 1.0 / 3.0
        }
    }
}

struct FormField: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var value = ""
    var width: FieldWidth = .half
    /// Visible lines in the box (1 = single-line field).
    var lines = 1
}

struct FormSettings: Codable, Equatable {
    var showTitleBar = true
    var fields: [FormField] = []
    var valueFontSize: Double = 13
}

/// Ready-made forms with sample wording (no real names); the user edits what differs.
struct FormTemplate: Identifiable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    let domain: String
    let place: String
    let duration: String
    let participants: String
    let description: String
    let goals: String

    func makeFields(hijriYear: String) -> [FormField] {
        [
            FormField(label: "المنفذ/ون", value: "", width: .half),
            FormField(label: "المشارك/ون", value: participants, width: .half),
            FormField(label: "مكان التنفيذ", value: place, width: .third),
            FormField(label: "مدة التنفيذ", value: duration, width: .third),
            FormField(label: "تاريخ التنفيذ", value: hijriYear, width: .third),
            FormField(label: "المستفيدون / العدد", value: "", width: .half),
            FormField(label: "المجال", value: domain, width: .half),
            FormField(label: "خطوات التنفيذ / الوصف", value: description, width: .half, lines: 7),
            FormField(label: "الأهداف", value: goals, width: .half, lines: 7)
        ]
    }

    static let blank = FormTemplate(
        id: "blank", title: "نموذج جديد", icon: "square.dashed", summary: "حقول أساسية فارغة",
        domain: "", place: "", duration: "", participants: "", description: "", goals: ""
    )

    /// Ready-made forms of the user's workplace (added when provided). Empty = only the blank form.
    static let all: [FormTemplate] = []
}
