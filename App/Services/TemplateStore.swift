import Foundation

/// Saved header templates (logo + administrative fields + frame), with one optional default
/// that is applied automatically to every new report.
@MainActor
final class TemplateStore: ObservableObject {
    @Published private(set) var templates: [HeaderTemplate] = []
    @Published var defaultTemplateID: UUID? {
        didSet { UserDefaults.standard.set(defaultTemplateID?.uuidString, forKey: Self.defaultKey) }
    }
    @Published var errorMessage: String?

    private static let defaultKey = "defaultTemplateID"
    private let fileURL: URL

    init() {
        DataVault.migrateLegacyDocuments()
        fileURL = DataVault.baseURL.appendingPathComponent("templates.tqr")
        defaultTemplateID = UserDefaults.standard.string(forKey: Self.defaultKey).flatMap(UUID.init(uuidString:))
        load()
    }

    var defaultTemplate: HeaderTemplate? {
        templates.first { $0.id == defaultTemplateID }
    }

    func add(_ template: HeaderTemplate) {
        templates.append(template)
        if defaultTemplateID == nil || defaultTemplate == nil {
            defaultTemplateID = template.id
        }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }), !name.trimmed.isEmpty else { return }
        templates[index].name = name.trimmed
        persist()
    }

    func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
        if defaultTemplateID == id {
            defaultTemplateID = templates.first?.id
        }
        persist()
    }

    func merge(_ incoming: [HeaderTemplate]) -> Int {
        var added = 0
        for template in incoming where !templates.contains(where: { $0.id == template.id }) {
            templates.append(template)
            added += 1
        }
        if defaultTemplate == nil { defaultTemplateID = templates.first?.id }
        persist()
        return added
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            templates = try JSONDecoder().decode([HeaderTemplate].self, from: DataVault.read(fileURL))
        } catch {
            errorMessage = "تعذر قراءة القوالب: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try DataVault.write(JSONEncoder().encode(templates), to: fileURL)
        } catch {
            errorMessage = "تعذر حفظ القوالب: \(error.localizedDescription)"
        }
    }
}
