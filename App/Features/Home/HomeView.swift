import SwiftUI
import UIKit

/// Home: two sections (reports / evidence forms), each a grid of cards showing the first page.
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

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("القسم", selection: $section) {
                        ForEach(ReportKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Button(action: createReport) {
                        NewReportBanner(
                            title: section == .text ? "تقرير جديد" : "نموذج شواهد جديد",
                            subtitle: section == .text
                                ? (templates.defaultTemplate.map { "بقالب «\($0.name)»" } ?? "اكتب مباشرة على صفحة A4")
                                : "قوالب جاهزة للمعلمين مع الصور والتوقيعات",
                            accent: theme.accent,
                            secondary: theme.secondary
                        )
                    }
                    .buttonStyle(.plain)

                    if visibleReports.isEmpty {
                        ContentUnavailableView(
                            section == .text ? "لا توجد تقارير بعد" : "لا توجد نماذج بعد",
                            systemImage: section == .text ? "doc.text" : "list.bullet.rectangle",
                            description: Text(section == .text ? "اضغط «تقرير جديد» للبدء." : "اختر قالباً جاهزاً مثل «إنجاز الدروس».")
                        )
                        .padding(.top, 30)
                    } else {
                        Text("المسودات")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(visibleReports) { report in
                                NavigationLink(value: report.id) {
                                    ReportCard(report: report)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { menu(for: report) }
                            }
                        }
                        Text("اضغط مطولاً على أي تقرير للنسخ أو الحذف.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 4) {
                        Text("تطوير \(AppInfo.developer) • الإصدار \(AppInfo.version)")
                            .foregroundStyle(.tertiary)
                        Link(destination: AppInfo.emailURL) {
                            Label(AppInfo.email, systemImage: "envelope")
                        }
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
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
                        Label("الإعدادات", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createReport) {
                        Label("جديد", systemImage: "plus")
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

    @ViewBuilder
    private func menu(for report: Report) -> some View {
        Button {
            if let copy = store.duplicateAsNew(report.id) { path.append(copy.id) }
        } label: {
            Label("تقرير جديد من هذا (بدون صور)", systemImage: "doc.badge.plus")
        }
        Button {
            store.duplicate(report.id)
        } label: {
            Label("نسخ", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            pendingDelete = report
        } label: {
            Label("حذف", systemImage: "trash")
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

private struct NewReportBanner: View {
    let title: String
    let subtitle: String
    let accent: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 44, height: 60)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "chevron.left").foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background(
            LinearGradient(colors: [accent, accent.opacity(0.78), secondary.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

/// A report card: thumbnail of its first page, title, page count and date.
private struct ReportCard: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportThumbnail(report: report)
                .aspectRatio(A4.aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            Text(report.title.trimmed.isEmpty ? "بدون عنوان" : report.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc").font(.caption2)
                Text("\(ArabicFormat.number(report.pages.count, report.page.numerals)) ص")
                Text("•")
                Text(report.updatedAt, format: .dateTime.day().month())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// First page drawn into a small bitmap, cached per report version.
private struct ReportThumbnail: View {
    let report: Report
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: report.updatedAt) {
            // Let the grid appear first, then draw.
            await Task.yield()
            image = ThumbnailCache.shared.image(for: report)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [UUID: (stamp: Date, image: UIImage)] = [:]

    func image(for report: Report) -> UIImage {
        if let cached = cache[report.id], cached.stamp == report.updatedAt { return cached.image }
        let snapshot = DocumentSnapshot(report: report, images: RenderImages(report: report))
        let width: CGFloat = 240
        let scale = width / A4.size.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: A4.size.height * scale), format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: A4.size.height * scale)))
            context.cgContext.scaleBy(x: scale, y: scale)
            PageRenderer.draw(page: 0, snapshot: snapshot, in: context.cgContext)
        }
        cache[report.id] = (report.updatedAt, image)
        return image
    }
}
