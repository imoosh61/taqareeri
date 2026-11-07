import SwiftUI
import UniformTypeIdentifiers

/// Templates, fonts and backup.
struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TemplatesView() } label: {
                        Label("قوالب الترويسة", systemImage: "rectangle.topthird.inset.filled")
                    }
                    NavigationLink { FontsView() } label: {
                        Label("الخطوط", systemImage: "textformat")
                    }
                    NavigationLink { BackupView() } label: {
                        Label("النسخ الاحتياطي والاستعادة", systemImage: "icloud.and.arrow.up")
                    }
                }
                Section("حول التطبيق") {
                    Text("تُحفظ المسودات تلقائياً على جهازك، وتظهر في تطبيق «الملفات» داخل مجلد التطبيق. استخدم النسخ الاحتياطي لحفظ نسخة في iCloud Drive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("المكتبة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}

struct TemplatesView: View {
    @EnvironmentObject private var templates: TemplateStore
    @State private var renaming: HeaderTemplate?
    @State private var newName = ""

    var body: some View {
        List {
            if templates.templates.isEmpty {
                ContentUnavailableView(
                    "لا توجد قوالب",
                    systemImage: "rectangle.topthird.inset.filled",
                    description: Text("من داخل أي تقرير: تبويب «الترويسة» ← «حفظ الترويسة كقالب ثابت».")
                )
            }
            ForEach(templates.templates) { template in
                Button {
                    templates.defaultTemplateID = template.id
                } label: {
                    HStack(spacing: 12) {
                        TransparentImagePreview(data: template.header.logoPNG, placeholder: "")
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.headline)
                            Text(template.header.ministry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if templates.defaultTemplateID == template.id {
                            Text("افتراضي")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        templates.delete(template.id)
                    } label: {
                        Label("حذف", systemImage: "trash")
                    }
                    Button {
                        newName = template.name
                        renaming = template
                    } label: {
                        Label("إعادة تسمية", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
            if !templates.templates.isEmpty {
                Section {
                    Button("بدون قالب افتراضي") { templates.defaultTemplateID = nil }
                } footer: {
                    Text("اضغط على قالب لجعله افتراضياً للتقارير الجديدة.")
                }
            }
        }
        .navigationTitle("قوالب الترويسة")
        .alert("إعادة تسمية القالب", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("الاسم", text: $newName)
            Button("حفظ") {
                if let template = renaming { templates.rename(template.id, to: newName) }
                renaming = nil
            }
            Button("إلغاء", role: .cancel) { renaming = nil }
        }
    }
}

struct FontsView: View {
    @EnvironmentObject private var fonts: FontRegistry
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(fonts.fonts) { font in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("بسم الله الرحمن الرحيم — تقرير رسمي ١٤٤٨هـ")
                            .font(.custom(font.postScriptName, size: 20))
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        if font.isImported {
                            Button(role: .destructive) {
                                fonts.deleteImported(font)
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                Text("خط Traditional Arabic مملوك لمايكروسوفت ولا يمكن تضمينه، لكن يمكنك استيراد ملفه المرخّص لديك (TTF/OTF) واستخدامه في تقاريرك.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("استيراد خط من الملفات", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("الخطوط")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.font]) { result in
            switch result {
            case .success(let url):
                do {
                    let font = try fonts.importFont(from: url)
                    message = "تمت إضافة الخط «\(font.displayName)»."
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسناً", role: .cancel) {}
        }
    }
}

struct BackupView: View {
    @EnvironmentObject private var store: ReportStore
    @EnvironmentObject private var templates: TemplateStore
    @State private var shareItem: IdentifiedURL?
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    do {
                        let url = try BackupService.makeBackupFile(reports: store.reports, templates: templates.templates)
                        shareItem = IdentifiedURL(url: url)
                    } catch {
                        message = "تعذر إنشاء النسخة: \(error.localizedDescription)"
                    }
                } label: {
                    Label("إنشاء نسخة احتياطية", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("اختر «حفظ في الملفات» ثم iCloud Drive لحفظ نسختك سحابياً.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("استعادة من نسخة احتياطية", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("تُدمج التقارير مع الموجودة؛ ويُحتفظ بالنسخة الأحدث عند التكرار.")
            }
        }
        .navigationTitle("النسخ الاحتياطي")
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let bundle = try BackupService.readBackup(from: url)
                    let reports = store.merge(bundle.reports)
                    let added = templates.merge(bundle.templates)
                    message = "تمت استعادة \(reports) تقرير و\(added) قالب."
                } catch {
                    message = "تعذر قراءة النسخة: \(error.localizedDescription)"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسناً", role: .cancel) {}
        }
    }
}
