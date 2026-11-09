import SwiftUI

/// Drafts list and the "new A4 report" entry point.
struct HomeView: View {
    @EnvironmentObject private var store: ReportStore
    @EnvironmentObject private var templates: TemplateStore
    @EnvironmentObject private var theme: ThemeStore
    @State private var path: [UUID] = []
    @State private var showLibrary = false
    @State private var pendingDelete: Report?
    @State private var showFormPicker = false
    @AppStorage("home.section") private var section: ReportKind = .text

    private var visibleReports: [Report] {
        store.reports.filter { $0.kind == section }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("القسم", selection: $section) {
                        ForEach(ReportKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                    Button(action: createReport) {
                        NewReportCard(
                            title: section == .text ? "تقرير جديد (A4)" : "نموذج شواهد جديد",
                            subtitle: section == .text
                                ? (templates.defaultTemplate.map { "باستخدام قالب «\($0.name)»" } ?? "ترويسة، إطار، كتابة، ثم تصدير PDF")
                                : "حقول جاهزة + صور وQR + توقيع المعلم والمدير",
                            accent: theme.accent,
                            secondary: theme.secondary
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    if visibleReports.isEmpty {
                        ContentUnavailableView(
                            section == .text ? "لا توجد تقارير بعد" : "لا توجد نماذج بعد",
                            systemImage: section == .text ? "doc.text" : "list.bullet.rectangle",
                            description: Text(section == .text ? "ابدأ بإنشاء تقرير جديد بمقاس A4." : "اختر قالباً جاهزاً مثل «إنجاز الدروس».")
                        )
                    }
                    ForEach(visibleReports) { report in
                        NavigationLink(value: report.id) {
                            ReportRow(report: report)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = report
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                if let copy = store.duplicateAsNew(report.id) { path.append(copy.id) }
                            } label: {
                                Label("تقرير جديد من هذا (بدون صور)", systemImage: "doc.badge.plus")
                            }
                            Button {
                                store.duplicate(report.id)
                            } label: {
                                Label("نسخ التقرير", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                pendingDelete = report
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("المسودات")
                } footer: {
                    VStack(spacing: 4) {
                        Text("تطوير \(AppInfo.developer) • الإصدار \(AppInfo.version)")
                            .foregroundStyle(.tertiary)
                        Link(destination: AppInfo.emailURL) {
                            Label(AppInfo.email, systemImage: "envelope")
                        }
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .navigationTitle("تقاريري")
            .navigationDestination(for: UUID.self) { id in
                if let report = store.report(id: id) {
                    ReportEditorView(report: report, store: store)
                } else {
                    ContentUnavailableView("التقرير غير موجود", systemImage: "questionmark.folder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLibrary = true
                    } label: {
                        Label("المكتبة والإعدادات", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createReport) {
                        Label("تقرير جديد", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showLibrary) {
                LibraryView()
            }
            .sheet(isPresented: $showFormPicker) {
                FormTemplatePicker { template in
                    // Navigate after the sheet has closed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { createForm(template) }
                }
            }
            .confirmationDialog(
                "حذف «\(pendingDelete?.title ?? "")»؟",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("حذف نهائياً", role: .destructive) {
                    if let report = pendingDelete { store.delete(report.id) }
                    pendingDelete = nil
                }
                Button("إلغاء", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("لا يمكن التراجع عن الحذف.")
            }
            .alert(
                "تنبيه",
                isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
            ) {
                Button("حسناً", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private func createReport() {
        if section == .form {
            showFormPicker = true
            return
        }
        let report = store.createReport(from: templates.defaultTemplate)
        path.append(report.id)
    }

    private func createForm(_ template: FormTemplate) {
        let report = store.createReport(from: templates.defaultTemplate, kind: .form, form: template)
        path.append(report.id)
    }
}

private struct NewReportCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 46, height: 62)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                RoundedRectangle(cornerRadius: 3)
                    .stroke(secondary, lineWidth: 1.5)
                    .frame(width: 38, height: 54)
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "chevron.left")
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background(
            LinearGradient(colors: [accent, accent.opacity(0.75), secondary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}

private struct ReportRow: View {
    let report: Report

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.kind == .text ? "doc.text.fill" : "list.bullet.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.title.trimmed.isEmpty ? "بدون عنوان" : report.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !report.header.ministry.trimmed.isEmpty {
                        Text(report.header.ministry).lineLimit(1)
                        Text("•")
                    }
                    Text(report.updatedAt, format: .dateTime.day().month().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
