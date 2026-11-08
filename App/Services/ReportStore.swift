import Foundation

/// Local persistence for reports: one JSON file per report in Documents/Reports
/// (visible in the Files app, so drafts can also be copied to iCloud Drive manually).
@MainActor
final class ReportStore: ObservableObject {
    @Published private(set) var reports: [Report] = []
    @Published var errorMessage: String?

    private let directory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let ioQueue = DispatchQueue(label: "com.imoosh61.officialreports.reports-io", qos: .utility)

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Reports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "تعذر إنشاء مجلد التقارير: \(error.localizedDescription)"
        }
        load()
    }

    func load() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        } catch {
            errorMessage = "تعذر قراءة التقارير: \(error.localizedDescription)"
            return
        }

        var loaded: [Report] = []
        var failures = 0
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                loaded.append(try decoder.decode(Report.self, from: data))
            } catch {
                failures += 1
            }
        }
        reports = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if failures > 0 {
            errorMessage = "تعذر فتح \(failures) من ملفات التقارير (قد تكون تالفة)."
        }
    }

    func report(id: UUID) -> Report? {
        reports.first { $0.id == id }
    }

    @discardableResult
    func save(_ report: Report) -> Bool {
        do {
            let data = try encoder.encode(report)
            try data.write(to: fileURL(for: report.id), options: [.atomic])
            if let index = reports.firstIndex(where: { $0.id == report.id }) {
                reports[index] = report
            } else {
                reports.append(report)
            }
            reports.sort { $0.updatedAt > $1.updatedAt }
            return true
        } catch {
            errorMessage = "تعذر حفظ التقرير: \(error.localizedDescription)"
            return false
        }
    }

    /// Updates the list immediately and writes the file on a background queue, so encoding large
    /// images (logo, frame, signatures) never blocks the interface. Writes stay in order.
    func saveInBackground(_ report: Report) {
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = report
        } else {
            reports.append(report)
        }
        reports.sort { $0.updatedAt > $1.updatedAt }

        let url = fileURL(for: report.id)
        ioQueue.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(report)
                try data.write(to: url, options: [.atomic])
            } catch {
                let message = "تعذر حفظ التقرير: \(error.localizedDescription)"
                Task { @MainActor in self?.errorMessage = message }
            }
        }
    }

    func createReport(from template: HeaderTemplate?) -> Report {
        var report = Report()
        if let template {
            var header = template.header
            header.date = Date()
            header.referenceNumber = ""
            header.attachments = ""
            report.header = header
            report.frame = template.frame
        }
        save(report)
        return report
    }

    func duplicate(_ id: UUID) {
        guard var copy = report(id: id) else { return }
        copy.id = UUID()
        copy.title += " (نسخة)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        save(copy)
    }

    func delete(_ id: UUID) {
        do {
            let url = fileURL(for: id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            reports.removeAll { $0.id == id }
        } catch {
            errorMessage = "تعذر حذف التقرير: \(error.localizedDescription)"
        }
    }

    /// Merges reports from a backup; keeps the newer copy when IDs collide. Returns the number written.
    func merge(_ incoming: [Report]) -> Int {
        var written = 0
        for report in incoming {
            if let existing = self.report(id: report.id), existing.updatedAt >= report.updatedAt { continue }
            if save(report) { written += 1 }
        }
        return written
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
