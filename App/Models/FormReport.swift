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

    static let all: [FormTemplate] = [
        FormTemplate(
            id: "lessons", title: "إنجاز الدروس", icon: "book.closed",
            summary: "توثيق إنجاز الدروس وفق الخطة",
            domain: "البيئة التعليمية والتحصيل الدراسي", place: "الفصول الدراسية", duration: "طوال العام الدراسي",
            participants: "جميع الطلاب",
            description: "تم إنجاز درس ( ... ) بتاريخ ( ... ) بتحقيق الهدف ( ... ) بنسبة إتقان ( ... )% وتمت متابعة غير المتقنين بخطة علاجية مصغّرة.",
            goals: "إتمام المقررات الدراسية وفق الخطة الزمنية المعتمدة، وضمان تسلسل المهارات وإتقانها، وتحقيق نواتج التعلم المستهدفة، وتوفير شواهد على انتظام العملية التعليمية."
        ),
        FormTemplate(
            id: "activity", title: "نشاط طلابي", icon: "figure.2.and.child.holdinghands",
            summary: "نشاط صفي أو لاصفي",
            domain: "الأنشطة الطلابية", place: "المدرسة", duration: "حصة دراسية",
            participants: "طلاب الصف ( ... )",
            description: "تم تنفيذ نشاط ( ... ) بمشاركة الطلاب، حيث شمل ( ... )، واختُتم النشاط بتقييم مشاركة الطلاب وتكريم المتميزين.",
            goals: "تنمية مهارات الطلاب وقدراتهم، وتعزيز روح التعاون والعمل الجماعي، وربط التعلم بالحياة، واكتشاف المواهب ورعايتها."
        ),
        FormTemplate(
            id: "remedial", title: "خطة علاجية", icon: "cross.case",
            summary: "علاج ضعف التحصيل",
            domain: "التحصيل الدراسي", place: "الفصل الدراسي", duration: "أسبوعان",
            participants: "الطلاب ذوو التحصيل المنخفض",
            description: "تم تشخيص مستوى الطلاب في مهارة ( ... ) عبر اختبار قبلي، ثم تطبيق أنشطة علاجية متدرجة وأوراق عمل فردية، وقياس التقدم باختبار بعدي.",
            goals: "معالجة الضعف في المهارات الأساسية، ورفع مستوى التحصيل الدراسي، ومراعاة الفروق الفردية، ومتابعة تقدم كل طالب."
        ),
        FormTemplate(
            id: "parents", title: "التواصل مع أولياء الأمور", icon: "person.2.wave.2",
            summary: "اجتماع أو تواصل مع الأسرة",
            domain: "الشراكة مع الأسرة", place: "المدرسة / عن بُعد", duration: "( ... ) دقيقة",
            participants: "أولياء أمور الطلاب",
            description: "تم التواصل مع أولياء أمور الطلاب عبر ( ... ) لمناقشة ( ... )، وتم الاتفاق على ( ... ) ومتابعة التنفيذ.",
            goals: "تعزيز الشراكة بين المدرسة والأسرة، وإطلاع أولياء الأمور على مستوى أبنائهم، والتعاون في معالجة الملاحظات ودعم التعلم."
        ),
        FormTemplate(
            id: "training", title: "حضور دورة / ورشة", icon: "graduationcap",
            summary: "التطوير المهني",
            domain: "النمو المهني", place: "( ... )", duration: "( ... ) ساعات",
            participants: "منسوبو المدرسة",
            description: "تم حضور دورة / ورشة بعنوان ( ... ) قدّمها ( ... )، وتناولت ( ... )، وسيتم تطبيق ما تم تعلمه في ( ... ).",
            goals: "تطوير الكفايات المهنية، ومواكبة المستجدات التربوية، وتحسين الممارسات التدريسية، ونقل أثر التدريب إلى الميدان."
        ),
        FormTemplate(
            id: "radio", title: "إذاعة مدرسية", icon: "mic",
            summary: "تقديم الإذاعة الصباحية",
            domain: "الأنشطة الطلابية", place: "ساحة المدرسة", duration: "الطابور الصباحي",
            participants: "طلاب الصف ( ... )",
            description: "تم تقديم الإذاعة المدرسية بعنوان ( ... ) وتضمنت فقرات: القرآن الكريم، والحديث الشريف، وكلمة الصباح، ( ... ).",
            goals: "تنمية مهارات الإلقاء والثقة بالنفس، وغرس القيم الإسلامية والوطنية، وتعزيز الانتماء للمدرسة."
        )
    ]
}
