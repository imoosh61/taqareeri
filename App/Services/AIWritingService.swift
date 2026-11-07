import Foundation

enum AIWritingTask: String, CaseIterable, Identifiable {
    case draft, formalize, proofread, summarize, expand, title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "كتابة تقرير من نقاط"
        case .formalize: return "صياغة رسمية"
        case .proofread: return "تدقيق لغوي"
        case .summarize: return "تلخيص"
        case .expand: return "توسيع وتفصيل"
        case .title: return "اقتراح عنوان"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: return "square.and.pencil"
        case .formalize: return "building.columns"
        case .proofread: return "checkmark.seal"
        case .summarize: return "text.badge.minus"
        case .expand: return "text.badge.plus"
        case .title: return "textformat"
        }
    }

    /// Tasks that work on existing report text (selection, or whole body).
    var needsSourceText: Bool { self != .draft }

    var instruction: String {
        switch self {
        case .draft:
            return "اكتب نص تقرير رسمي كامل ومترابط بناءً على المعطيات والنقاط التالية. ابدأ بتمهيد مناسب، ثم عرض منظم للمحتوى في فقرات، ثم خاتمة أو توصيات عند الحاجة."
        case .formalize:
            return "أعد صياغة النص التالي بأسلوب إداري رسمي فصيح ومناسب للمراسلات الحكومية، مع الحفاظ على المعنى والمعلومات كما هي."
        case .proofread:
            return "دقّق النص التالي إملائياً ونحوياً وصحّح علامات الترقيم فقط، دون تغيير الأسلوب أو المعنى، وأعد النص كاملاً بعد التصحيح."
        case .summarize:
            return "لخّص النص التالي في فقرة أو فقرتين موجزتين بأسلوب رسمي، مع إبقاء النقاط الجوهرية."
        case .expand:
            return "وسّع النص التالي بتفصيل مناسب وإضافة ما يلزم من توضيح منطقي بأسلوب رسمي، دون اختلاق أرقام أو وقائع غير مذكورة."
        case .title:
            return "اقترح عنواناً رسمياً واحداً موجزاً ومناسباً لتقرير بالمحتوى التالي. أعد العنوان فقط في سطر واحد."
        }
    }
}

enum AIModelOption: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case opus = "claude-opus-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sonnet: return "Sonnet — متوازن (موصى به)"
        case .haiku: return "Haiku — الأسرع والأرخص"
        case .opus: return "Opus — الأعلى جودة"
        }
    }
}

enum AIWritingError: LocalizedError {
    case missingKey
    case invalidKey
    case rateLimited
    case overloaded
    case server(String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "أضف مفتاح Claude API من «المكتبة ← الذكاء الاصطناعي» أولاً."
        case .invalidKey: return "مفتاح API غير صحيح أو منتهي. تحقق منه في الإعدادات."
        case .rateLimited: return "تم تجاوز حد الطلبات أو الرصيد. حاول بعد قليل أو تحقق من رصيد حسابك."
        case .overloaded: return "الخدمة مزدحمة حالياً، حاول مرة أخرى بعد لحظات."
        case .server(let message): return "خطأ من الخدمة: \(message)"
        case .emptyResponse: return "لم يصل رد من الخدمة."
        case .network(let message): return "تعذر الاتصال: \(message)"
        }
    }
}

/// Settings for the AI writer (model in UserDefaults, API key in the Keychain).
enum AISettings {
    private static let keyAccount = "anthropic.apiKey"
    private static let modelKey = "ai.model"

    static var apiKey: String? {
        get { KeychainStore.string(for: keyAccount) }
        set { KeychainStore.set(newValue?.trimmed, for: keyAccount) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? AIModelOption.sonnet.rawValue }
        set { UserDefaults.standard.set(newValue.trimmed, forKey: modelKey) }
    }

    static var hasKey: Bool { !(apiKey ?? "").isEmpty }
}

/// Context about the report sent with each request so output fits the organisation.
struct AIReportContext {
    var title: String
    var ministry: String
    var administration: String
    var department: String
}

/// Calls the Claude Messages API. Only invoked on explicit user action.
struct AIWritingService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func run(task: AIWritingTask, input: String, context: AIReportContext) async throws -> String {
        guard let apiKey = AISettings.apiKey, !apiKey.isEmpty else { throw AIWritingError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": AISettings.model,
            "max_tokens": task == .title ? 100 : 3000,
            "system": systemPrompt(context),
            "messages": [
                ["role": "user", "content": "\(task.instruction)\n\n«النص»:\n\(input)"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIWritingError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            switch status {
            case 401, 403: throw AIWritingError.invalidKey
            case 429: throw AIWritingError.rateLimited
            case 529, 503: throw AIWritingError.overloaded
            default: throw AIWritingError.server(message)
            }
        }

        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        let cleaned = Self.stripMarkdown(text)
        guard !cleaned.isEmpty else { throw AIWritingError.emptyResponse }
        return cleaned
    }

    private func systemPrompt(_ context: AIReportContext) -> String {
        var lines = [
            "أنت كاتب تقارير ومراسلات رسمية حكومية محترف باللغة العربية الفصحى.",
            "اكتب بأسلوب إداري رسمي واضح ومهذب، دون مبالغة.",
            "أعد النص النهائي فقط، دون مقدمات أو شرح أو تعليقات منك.",
            "لا تستخدم تنسيق Markdown إطلاقاً (لا # ولا ** ولا جداول). افصل الفقرات بسطر جديد واحد. إن احتجت تعداداً فاستخدم (أولاً، ثانياً) أو أرقاماً متبوعة بشرطة.",
            "لا تختلق أسماء أو أرقاماً أو تواريخ غير مذكورة؛ ضع مكانها نقاطاً (...) ليكملها المستخدم.",
            "لا تكتب الترويسة أو التوقيع أو التاريخ؛ فهي تُضاف تلقائياً في التطبيق."
        ]
        let parts = [
            context.ministry.trimmed.isEmpty ? nil : "الجهة: \(context.ministry.trimmed)",
            context.administration.trimmed.isEmpty ? nil : "الإدارة: \(context.administration.trimmed)",
            context.department.trimmed.isEmpty ? nil : "القسم: \(context.department.trimmed)",
            context.title.trimmed.isEmpty ? nil : "عنوان التقرير: \(context.title.trimmed)"
        ].compactMap { $0 }
        if !parts.isEmpty {
            lines.append("سياق التقرير — " + parts.joined(separator: "، "))
        }
        return lines.joined(separator: "\n")
    }

    /// Defensive cleanup in case the model still emits Markdown.
    static func stripMarkdown(_ text: String) -> String {
        var result: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
            while line.hasPrefix("#") { line.removeFirst() }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }
            result.append(line.trimmingCharacters(in: .whitespaces))
        }
        // Collapse runs of blank lines into paragraph breaks.
        var collapsed: [String] = []
        for line in result {
            if line.isEmpty && (collapsed.last?.isEmpty ?? true) { continue }
            collapsed.append(line)
        }
        return collapsed.filter { !$0.isEmpty }.joined(separator: "\n").trimmed
    }
}
