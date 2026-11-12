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
    @State private var showLogoPlacement = false

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

            if vm.report.kind == .text {
                addresseeSection
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
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .fullScreenCover(isPresented: $showLogoPlacement) {
            LogoPlacementEditor(vm: vm)
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

            if vm.report.header.logoPNG != nil {
                Button {
                    vm.repaginate()
                    showLogoPlacement = true
                } label: {
                    Label("تحريك الشعار بحرية", systemImage: "hand.draw")
                }
                .disabled(!vm.report.header.isEnabled)
                if vm.report.header.logoOffset != .zero {
                    Button("إرجاع الشعار للمنتصف", role: .destructive) {
                        vm.resetLogoPosition()
                    }
                }
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
        let visible = context.pagination.spec.headerRect(bodyPage: 0).maxY + 10
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

/// Drag the logo anywhere on the first page; drag the corner handle to resize it.
struct LogoPlacementEditor: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var moveOffset: CGSize = .zero
    @State private var growOffset: CGFloat = 0
    @State private var isInteracting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("اسحب الشعار إلى المكان الذي تريده، واسحب الزاوية لتكبيره أو تصغيره.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let box = vm.logoBox() {
                    GeometryReader { proxy in
                        let pageWidth = min(proxy.size.width - 16, (proxy.size.height - 8) * A4.aspectRatio)
                        let scale = pageWidth / A4.size.width
                        let pageHeight = pageWidth / A4.aspectRatio

                        ZStack(alignment: .topLeading) {
                            A4PageView(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                                .frame(width: pageWidth, height: pageHeight)
                            handle(box, scale: scale)
                        }
                        .frame(width: pageWidth, height: pageHeight)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 8)

                    nudgePad
                } else {
                    ContentUnavailableView("لا يوجد شعار ظاهر", systemImage: "photo",
                                           description: Text("أضف شعاراً وفعّل الترويسة أولاً."))
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .navigationTitle("مكان الشعار")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("المنتصف") { vm.resetLogoPosition() }
                        .disabled(vm.report.header.logoOffset == .zero)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    private func handle(_ box: CGRect, scale: CGFloat) -> some View {
        let side = max(box.width * scale + growOffset, 24)
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.accent.opacity(isInteracting ? 0.18 : 0.06))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: isInteracting ? [] : [5, 3]))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            moveOffset = value.translation
                        }
                        .onEnded { value in
                            vm.adjustLogo(move: CGSize(width: value.translation.width / scale,
                                                       height: value.translation.height / scale), grow: 0)
                            moveOffset = .zero
                            isInteracting = false
                        }
                )
            Circle()
                .fill(theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.bold)).foregroundStyle(.white))
                .offset(x: 10, y: 10)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            growOffset = (value.translation.width + value.translation.height) / 2
                        }
                        .onEnded { value in
                            let grow = (value.translation.width + value.translation.height) / 2
                            vm.adjustLogo(move: .zero, grow: grow / scale)
                            growOffset = 0
                            isInteracting = false
                        }
                )
        }
        .frame(width: side, height: side)
        .offset(x: box.minX * scale + moveOffset.width, y: box.minY * scale + moveOffset.height)
    }

    /// Fine positioning in 2-point steps.
    private var nudgePad: some View {
        HStack(spacing: 8) {
            nudge("chevron.left") { vm.adjustLogo(move: CGSize(width: -2, height: 0), grow: 0) }
            nudge("chevron.up") { vm.adjustLogo(move: CGSize(width: 0, height: -2), grow: 0) }
            nudge("chevron.down") { vm.adjustLogo(move: CGSize(width: 0, height: 2), grow: 0) }
            nudge("chevron.right") { vm.adjustLogo(move: CGSize(width: 2, height: 0), grow: 0) }
            Divider().frame(height: 28)
            nudge("minus.magnifyingglass") { vm.adjustLogo(move: .zero, grow: -4) }
            nudge("plus.magnifyingglass") { vm.adjustLogo(move: .zero, grow: 4) }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}
