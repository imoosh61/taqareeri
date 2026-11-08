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
    @State private var zoomPage: PageRef?

    var body: some View {
        Form {
            Section {
                A4PageView(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .onTapGesture { zoomPage = PageRef(id: vm.firstBodyPhysicalPage) }
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

            Section {
                TextField("السطر العلوي", text: $vm.report.header.topLine)
                TextField("اسم الوزارة / الجهة", text: $vm.report.header.ministry)
                TextField("الإدارة العامة", text: $vm.report.header.generalAdministration)
                TextField("القسم", text: $vm.report.header.department)
                HeaderStripPreview(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                FontSizeSlider(
                    title: "حجم خط البيانات الإدارية",
                    value: $vm.report.header.adminFontSize,
                    defaultValue: HeaderInfo.defaultAdminFontSize,
                    numerals: vm.report.page.numerals
                )
                HorizontalPositionControl(
                    title: "موضع البيانات الإدارية",
                    offset: $vm.report.header.adminOffset,
                    alignment: $vm.report.header.adminAlignment
                )
            } header: {
                Text("الجانب الأيمن — البيانات الإدارية")
            } footer: {
                Text("إذا كان النص أطول من المساحة يُصغَّر الخط تلقائياً حتى لا يختفي أي سطر.")
            }

            Section {
                DatePicker("التاريخ", selection: $vm.report.header.date, displayedComponents: .date)
                Picker("نوع التاريخ", selection: $vm.report.header.dateMode) {
                    ForEach(DateMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("إظهار اليوم", isOn: $vm.report.header.showDayName)
                HeaderStripPreview(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                FontSizeSlider(
                    title: "حجم خط التاريخ والرقم",
                    value: $vm.report.header.dateFontSize,
                    defaultValue: HeaderInfo.defaultDateFontSize,
                    numerals: vm.report.page.numerals
                )
                HorizontalPositionControl(
                    title: "موضع التاريخ والرقم",
                    offset: $vm.report.header.dateOffset,
                    alignment: $vm.report.header.dateAlignment
                )
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

            addresseeSection

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
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
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

    private var addresseeSection: some View {
        Section {
            Toggle("إضافة جهة موجَّه إليها", isOn: $vm.report.addressee.isEnabled)
            if vm.report.addressee.isEnabled {
                TextField("المخاطَب (مثال: سعادة مدير إدارة المساجد بالحرث)", text: $vm.report.addressee.recipientTitle, axis: .vertical)
                TextField("اسم المسؤول (مثال: الأستاذ/ ...)", text: $vm.report.addressee.recipientName)
                FontSizeSlider(
                    title: "حجم خط المخاطَب والاسم",
                    value: Binding(
                        get: { vm.report.addresseeFontSize },
                        set: { vm.report.addressee.fontSizeValue = $0 }
                    ),
                    defaultValue: min(max(vm.report.textStyle.fontSize, 11), 24),
                    numerals: vm.report.page.numerals,
                    range: 9...30
                )

                Toggle("إظهار عبارة التبجيل في يسار السطر", isOn: $vm.report.addressee.showHonorific)
                if vm.report.addressee.showHonorific {
                    HStack {
                        TextField("العبارة", text: $vm.report.addressee.honorific)
                        Menu {
                            ForEach(AddresseeSettings.honorificSuggestions, id: \.self) { phrase in
                                Button(phrase) { vm.report.addressee.honorific = phrase }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                }

                Toggle("إظهار التحية", isOn: $vm.report.addressee.showGreeting)
                if vm.report.addressee.showGreeting {
                    TextField("التحية", text: $vm.report.addressee.greeting, axis: .vertical)
                }
            }
        } header: {
            Text("الموجَّه إليه (اختياري)")
        } footer: {
            Text("يظهر أعلى أول صفحة قبل نص التقرير: المخاطَب، ثم الاسم يميناً و«حفظه الله» في يسار السطر نفسه، ثم التحية.")
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

            if vm.report.header.logoPNG != nil {
                HeaderStripPreview(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("حجم الشعار")
                        Spacer()
                        Text("\(ArabicFormat.number(Int((vm.report.header.logoScale * 100).rounded()), vm.report.page.numerals))٪")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if vm.report.header.logoScale != 1 {
                            Button {
                                vm.report.header.logoScale = 1
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("الحجم الافتراضي")
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                        Slider(value: $vm.report.header.logoScale, in: HeaderInfo.logoScaleRange, step: 0.05)
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.vertical, 4)
            }

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

/// Font size slider with live value and a reset-to-default button.
struct FontSizeSlider: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let numerals: NumeralStyle
    var range: ClosedRange<Double> = 7...20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(ArabicFormat.number(Int(value.rounded()), numerals))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if value != defaultValue {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("الحجم الافتراضي")
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: $value, in: range, step: 0.5)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Moves a header block left / right and sets its text alignment.
struct HorizontalPositionControl: View {
    let title: String
    @Binding var offset: Double
    @Binding var alignment: ParagraphAlignment

    private let alignments: [ParagraphAlignment] = [.left, .center, .right]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if offset != 0 {
                    Button {
                        offset = 0
                    } label: {
                        Label("الوضع الأصلي", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                nudge("chevron.left") { offset = max(offset - 2, -160) }
                Text("يسار").font(.caption).foregroundStyle(.secondary)
                Slider(value: $offset, in: -160...160, step: 1)
                Text("يمين").font(.caption).foregroundStyle(.secondary)
                nudge("chevron.right") { offset = min(offset + 2, 160) }
            }
            .environment(\.layoutDirection, .leftToRight)

            Picker("محاذاة النص", selection: $alignment) {
                ForEach(alignments) { item in
                    Image(systemName: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 4)
    }

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}

/// The top strip of a page (letterhead area) so header changes are visible while editing below.
struct HeaderStripPreview: View {
    let page: Int
    let context: PageRenderContext

    var body: some View {
        let visible = context.pagination.spec.headerRect.maxY + 10
        GeometryReader { proxy in
            let width = proxy.size.width
            A4PageView(page: page, context: context)
                .frame(width: width, height: width / A4.aspectRatio)
                .frame(width: width, height: visible * width / A4.size.width, alignment: .top)
                .clipped()
        }
        .aspectRatio(A4.size.width / visible, contentMode: .fit)
    }
}
