import PhotosUI
import SwiftUI

/// Step 1 of the journey: report title, letterhead (logo, administrative data, date/reference),
/// cover page and header templates.
struct HeaderEditorView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var templates: TemplateStore

    @State private var logoItem: PhotosPickerItem?
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var confirmation: String?

    var body: some View {
        Form {
            Section {
                A4PageView(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("التقرير") {
                TextField("عنوان التقرير", text: $vm.report.title)
            }

            Section {
                Toggle("إظهار الترويسة", isOn: $vm.report.header.isEnabled)
                Picker("مكان الترويسة", selection: $vm.report.header.placement) {
                    ForEach(HeaderPlacement.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!vm.report.header.isEnabled)
            } header: {
                Text("الترويسة العلوية")
            }

            logoSection

            Section("الجانب الأيمن — البيانات الإدارية") {
                TextField("السطر العلوي", text: $vm.report.header.topLine)
                TextField("اسم الوزارة / الجهة", text: $vm.report.header.ministry)
                TextField("الإدارة العامة", text: $vm.report.header.generalAdministration)
                TextField("القسم", text: $vm.report.header.department)
            }

            Section {
                DatePicker("التاريخ", selection: $vm.report.header.date, displayedComponents: .date)
                Picker("نوع التاريخ", selection: $vm.report.header.dateMode) {
                    ForEach(DateMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("إظهار اليوم", isOn: $vm.report.header.showDayName)
                TextField("الرقم المرجعي", text: $vm.report.header.referenceNumber)
                TextField("المرفقات (اختياري)", text: $vm.report.header.attachments)
                Picker("شكل الأرقام", selection: $vm.report.page.numerals) {
                    ForEach(NumeralStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("الجانب الأيسر — التوثيق والزمن")
            } footer: {
                Text(ArabicFormat.headerDateLines(vm.report.header, numerals: vm.report.page.numerals).joined(separator: "\n"))
            }

            Section {
                Toggle("صفحة غلاف رسمية", isOn: $vm.report.cover.isEnabled)
                if vm.report.cover.isEnabled {
                    TextField("عنوان فرعي (اختياري)", text: $vm.report.cover.subtitle)
                    TextField("إعداد (اسم المعد أو الجهة)", text: $vm.report.cover.preparedBy)
                }
            } header: {
                Text("الغلاف")
            } footer: {
                Text("تُضاف صفحة أولى تحمل الشعار واسم الجهة وعنوان التقرير والتاريخ.")
            }

            Section {
                Button {
                    templateName = vm.report.header.ministry
                    showSaveTemplate = true
                } label: {
                    Label("حفظ الترويسة كقالب ثابت", systemImage: "square.and.arrow.down")
                }
                if !templates.templates.isEmpty {
                    Menu {
                        ForEach(templates.templates) { template in
                            Button(template.name) {
                                vm.applyTemplate(template)
                                confirmation = "تم تطبيق قالب «\(template.name)»."
                            }
                        }
                    } label: {
                        Label("تطبيق قالب محفوظ", systemImage: "square.on.square")
                    }
                }
            } header: {
                Text("القوالب")
            } footer: {
                Text("القالب الافتراضي يُطبَّق تلقائياً على كل تقرير جديد، فلا تحتاج لإعادة إدخال البيانات.")
            }
        }
        .alert("حفظ كقالب", isPresented: $showSaveTemplate) {
            TextField("اسم القالب", text: $templateName)
            Button("حفظ") {
                let template = vm.makeTemplate(named: templateName)
                templates.add(template)
                confirmation = templates.defaultTemplateID == template.id
                    ? "حُفظ القالب وأصبح افتراضياً للتقارير الجديدة."
                    : "حُفظ القالب «\(template.name)»."
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يحفظ الشعار وبيانات الجهة والإطار.")
        }
        .alert(
            confirmation ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
        ) {
            Button("حسناً", role: .cancel) {}
        }
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await vm.importLogo(data)
                } else {
                    vm.errorMessage = "تعذر تحميل الصورة المختارة."
                }
                logoItem = nil
            }
        }
    }

    private var logoSection: some View {
        Section {
            HStack {
                Spacer()
                TransparentImagePreview(data: vm.report.header.logoPNG, placeholder: "لا يوجد شعار")
                    .frame(width: 130, height: 130)
                    .overlay {
                        if vm.isProcessingImage {
                            ProgressView()
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                Spacer()
            }
            .padding(.vertical, 4)

            PhotosPicker(selection: $logoItem, matching: .images) {
                Label(vm.report.header.logoPNG == nil ? "رفع الشعار من الصور" : "تغيير الشعار", systemImage: "photo.badge.plus")
            }

            Picker("تفريغ الخلفية", selection: $vm.logoRemovalMode) {
                ForEach(LogoBackgroundMode.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: vm.logoRemovalMode) {
                Task { await vm.reprocessLogo() }
            }

            if vm.report.header.logoPNG != nil {
                Button(role: .destructive) {
                    vm.removeLogo()
                } label: {
                    Label("حذف الشعار", systemImage: "trash")
                }
            }
        } header: {
            Text("الشعار (المنتصف)")
        } footer: {
            Text("التفريغ الذكي يزيل الخلفية البيضاء المتصلة بأطراف الصورة فقط ويحافظ على الأجزاء البيضاء داخل الشعار.")
        }
    }
}
