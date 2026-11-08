import SwiftUI
import UIKit
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
                Section {
                    NavigationLink { AppearanceView() } label: {
                        Label("ألوان التطبيق والمظهر", systemImage: "paintpalette")
                    }
                    NavigationLink { AISettingsView() } label: {
                        Label("الذكاء الاصطناعي", systemImage: "sparkles")
                    }
                }
                Section {
                    LabeledContent("التطبيق", value: "تقاريري")
                    LabeledContent("الإصدار", value: AppInfo.version)
                    LabeledContent("تطوير", value: AppInfo.developer)
                    Link(destination: AppInfo.emailURL) {
                        LabeledContent("مراسلة المطوّر") {
                            Label(AppInfo.email, systemImage: "envelope.fill")
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    Text("تُحفظ المسودات تلقائياً على جهازك، وتظهر في تطبيق «الملفات» داخل مجلد التطبيق. استخدم النسخ الاحتياطي لحفظ نسخة في iCloud Drive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("حول التطبيق")
                } footer: {
                    Text(AppInfo.copyright)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
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
    @EnvironmentObject private var theme: ThemeStore
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
                                .background(theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(theme.accent)
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
            ForEach(fonts.grouped, id: \.category) { group in
              Section(group.category.title) {
                ForEach(group.fonts) { font in
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
              }
            }

            Section {
                EmptyView()
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

/// App colours: accent (buttons, selection, home card) and secondary, plus light/dark mode.
struct AppearanceView: View {
    @EnvironmentObject private var theme: ThemeStore

    private var accentBinding: Binding<Color> {
        Binding(get: { theme.accent }, set: { theme.accentHex = UIColor($0).hexString })
    }

    private var secondaryBinding: Binding<Color> {
        Binding(get: { theme.secondary }, set: { theme.secondaryHex = UIColor($0).hexString })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [theme.accent, theme.accent.opacity(0.75), theme.secondary.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 64)
                        .overlay(Text("تقاريري").font(.title3.weight(.bold)).foregroundStyle(.white))
                }
                .listRowBackground(Color.clear)
            }

            Section("اللون الرئيسي") {
                palette(selected: theme.accentHex) { theme.accentHex = $0 }
                ColorPicker("لون مخصص", selection: accentBinding, supportsOpacity: false)
            }

            Section("اللون الثانوي") {
                palette(selected: theme.secondaryHex) { theme.secondaryHex = $0 }
                ColorPicker("لون مخصص", selection: secondaryBinding, supportsOpacity: false)
            }

            Section("المظهر") {
                Picker("المظهر", selection: $theme.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("استعادة الألوان الافتراضية", role: .destructive) { theme.reset() }
            }
        }
        .navigationTitle("ألوان التطبيق")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func palette(selected: String, onSelect: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 10)], spacing: 10) {
            ForEach(ThemeStore.palette, id: \.self) { hex in
                Button {
                    onSelect(hex)
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .opacity(selected.uppercased() == hex ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
