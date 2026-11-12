import PhotosUI
import SwiftUI

/// Everything about the top of the page, grouped into short sub-pages instead of one long list:
/// title, logo, administrative data, date, organisation paper, frame, addressee, templates.
struct LetterheadSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var templates: TemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveTemplate = false
    @State private var templateName = ""
    @State private var confirmation: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HeaderStripPreview(snapshot: vm.snapshot)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section("عنوان التقرير") {
                    TextField("العنوان", text: $vm.report.title)
                }

                Section {
                    Toggle("إظهار الترويسة", isOn: $vm.report.header.isEnabled)
                    if vm.report.header.isEnabled {
                        Picker("تظهر في", selection: $vm.report.header.placement) {
                            ForEach(HeaderPlacement.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    link("الشعار", icon: "seal", detail: vm.report.header.logoPNG == nil ? "بدون" : nil) { LogoPage(vm: vm) }
                    link("بيانات الجهة", icon: "building.columns", detail: vm.report.header.ministry.trimmed.isEmpty ? nil : vm.report.header.ministry) {
                        AdministrativePage(vm: vm)
                    }
                    link("التاريخ والرقم", icon: "calendar", detail: vm.report.header.showDate ? nil : "مخفي") { DatePage(vm: vm) }
                } header: {
                    Text("الترويسة")
                } footer: {
                    Text("يمكنك أيضاً سحب الشعار مباشرة على الصفحة وتغيير حجمه من الزاوية.")
                }

                Section("الشكل") {
                    link("ورق الجهة (صورة أعلى وأسفل الصفحة)", icon: "rectangle.tophalf.inset.filled",
                         detail: vm.report.frame.hasLetterhead ? "مفعّل" : nil) { OrganisationPaperPage(vm: vm) }
                    link("الإطار", icon: "square.dashed", detail: vm.report.frame.style.title) { FramePage(vm: vm) }
                    if vm.report.kind == .text {
                        link("الموجَّه إليه", icon: "person.text.rectangle",
                             detail: vm.report.addressee.isEnabled ? "مفعّل" : nil) { AddresseePage(vm: vm) }
                    }
                }

                Section {
                    Button {
                        templateName = vm.report.header.ministry
                        showSaveTemplate = true
                    } label: {
                        Label("حفظ كقالب للتقارير الجديدة", systemImage: "square.and.arrow.down")
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
                    Text("القالب يحفظ الشعار وبيانات الجهة وورق الجهة والإطار، ويُطبَّق تلقائياً على كل تقرير جديد.")
                }
            }
            .navigationTitle("الترويسة والشكل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
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
            }
            .alert(confirmation ?? "", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                Button("حسناً", role: .cancel) {}
            }
        }
    }

    private func link<Destination: View>(_ title: String, icon: String, detail: String?, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: icon)
                if let detail {
                    Spacer()
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Sub-pages

/// Shared layout: sticky letterhead preview + form.
private struct EditingPage<Content: View>: View {
    @ObservedObject var vm: ReportEditorViewModel
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                HeaderStripPreview(snapshot: vm.snapshot)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LogoPage: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var item: PhotosPickerItem?

    var body: some View {
        EditingPage(vm: vm, title: "الشعار") {
            Section {
                HStack {
                    Spacer()
                    TransparentImagePreview(data: vm.report.header.logoPNG, placeholder: "لا يوجد شعار")
                        .frame(width: 120, height: 120)
                        .overlay { if vm.isProcessingImage { ProgressView() } }
                    Spacer()
                }
                PhotosPicker(selection: $item, matching: .images) {
                    Label(vm.report.header.logoPNG == nil ? "رفع الشعار من الصور" : "تغيير الشعار", systemImage: "photo.badge.plus")
                }
                Picker("تفريغ الخلفية", selection: $vm.logoRemovalMode) {
                    ForEach(LogoBackgroundMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: vm.logoRemovalMode) {
                    Task { await vm.reprocessLogo() }
                }
            } footer: {
                Text("التفريغ الذكي يزيل الخلفية البيضاء حول الشعار ويحافظ على الأجزاء البيضاء داخله.")
            }

            if vm.report.header.logoPNG != nil {
                Section {
                    FontSizeSlider(title: "حجم الشعار ٪", value: Binding(
                        get: { vm.report.header.logoScale * 100 },
                        set: { vm.report.header.logoScale = $0 / 100 }
                    ), defaultValue: 100, numerals: vm.report.page.numerals,
                       range: HeaderInfo.logoScaleRange.lowerBound * 100...HeaderInfo.logoScaleRange.upperBound * 100)
                    Button("إرجاع الشعار لمكانه وحجمه الأصلي") { vm.resetLogoPosition() }
                    Button("حذف الشعار", role: .destructive) { vm.removeLogo() }
                } footer: {
                    Text("لتحريك الشعار: اضغط عليه في الصفحة ثم اسحبه.")
                }
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await vm.importLogo(data)
                } else {
                    vm.errorMessage = "تعذر تحميل الصورة المختارة."
                }
                item = nil
            }
        }
    }
}

private struct AdministrativePage: View {
    @ObservedObject var vm: ReportEditorViewModel

    var body: some View {
        EditingPage(vm: vm, title: "بيانات الجهة") {
            Section("النص (يمين الترويسة)") {
                TextField("السطر العلوي", text: $vm.report.header.topLine)
                TextField("اسم الوزارة / الجهة", text: $vm.report.header.ministry)
                TextField("الإدارة العامة", text: $vm.report.header.generalAdministration)
                TextField("القسم", text: $vm.report.header.department)
            }
            Section {
                FontSizeSlider(title: "حجم الخط", value: $vm.report.header.adminFontSize,
                               defaultValue: HeaderInfo.defaultAdminFontSize, numerals: vm.report.page.numerals)
                HorizontalPositionControl(title: "الموضع", offset: $vm.report.header.adminOffset,
                                          alignment: $vm.report.header.adminAlignment)
            } footer: {
                Text("إذا كان النص أطول من المساحة يُصغَّر الخط تلقائياً حتى لا يختفي أي سطر.")
            }
        }
    }
}

private struct DatePage: View {
    @ObservedObject var vm: ReportEditorViewModel

    var body: some View {
        EditingPage(vm: vm, title: "التاريخ والرقم") {
            Section("التاريخ (يسار الترويسة)") {
                Toggle("إظهار التاريخ", isOn: $vm.report.header.showDate)
                if vm.report.header.showDate {
                    DatePicker("التاريخ", selection: $vm.report.header.date, displayedComponents: .date)
                    Picker("النوع", selection: $vm.report.header.dateMode) {
                        ForEach(DateMode.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("إظهار اليوم", isOn: $vm.report.header.showDayName)
                }
                TextField("الرقم المرجعي", text: $vm.report.header.referenceNumber)
                TextField("المرفقات (اختياري)", text: $vm.report.header.attachments)
                Picker("الأرقام", selection: $vm.report.page.numerals) {
                    ForEach(NumeralStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                FontSizeSlider(title: "حجم الخط", value: $vm.report.header.dateFontSize,
                               defaultValue: HeaderInfo.defaultDateFontSize, numerals: vm.report.page.numerals)
                HorizontalPositionControl(title: "الموضع", offset: $vm.report.header.dateOffset,
                                          alignment: $vm.report.header.dateAlignment)
            }
        }
    }
}

private struct OrganisationPaperPage: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var topItem: PhotosPickerItem?
    @State private var bottomItem: PhotosPickerItem?

    var body: some View {
        EditingPage(vm: vm, title: "ورق الجهة") {
            Section {
                imageControls(top: true)
            } header: {
                Text("صورة أعلى الصفحة")
            } footer: {
                Text("مثل شريط اسم الشركة وشعارها. تُزال الحواف البيضاء والسوداء تلقائياً.")
            }
            Section("صورة أسفل الصفحة") {
                imageControls(top: false)
            }
            if vm.report.frame.hasLetterhead {
                Section {
                    Toggle("على كل الصفحات", isOn: $vm.report.frame.letterheadAllPages)
                    Toggle("إظهار الشعار وبيانات الترويسة أيضاً", isOn: $vm.report.header.isEnabled)
                }
            }
        }
        .onChange(of: topItem) { _, item in load(item, top: true); topItem = nil }
        .onChange(of: bottomItem) { _, item in load(item, top: false); bottomItem = nil }
    }

    @ViewBuilder
    private func imageControls(top: Bool) -> some View {
        let data = top ? vm.report.frame.letterheadTopPNG : vm.report.frame.letterheadBottomPNG
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 70)
                .padding(6)
                .background(CheckerboardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 8))
            FontSizeSlider(title: "العرض ٪", value: Binding(
                get: { (top ? vm.report.frame.letterheadTopScale : vm.report.frame.letterheadBottomScale) * 100 },
                set: { value in
                    if top { vm.report.frame.letterheadTopScale = value / 100 } else { vm.report.frame.letterheadBottomScale = value / 100 }
                }
            ), defaultValue: 100, numerals: vm.report.page.numerals,
               range: FrameSettings.letterheadScaleRange.lowerBound * 100...FrameSettings.letterheadScaleRange.upperBound * 100)
            VerticalPositionControl(
                offset: top ? $vm.report.frame.letterheadTopOffset : $vm.report.frame.letterheadBottomOffset,
                range: top ? FrameSettings.letterheadTopOffsetRange : FrameSettings.letterheadBottomOffsetRange
            )
            Button("حذف الصورة", role: .destructive) { vm.removeLetterhead(top: top) }
        }
        PhotosPicker(selection: top ? $topItem : $bottomItem, matching: .images) {
            Label(data == nil ? "رفع من الصور" : "تغيير الصورة", systemImage: "photo.badge.plus")
        }
        if vm.isProcessingImage { ProgressView() }
    }

    private func load(_ item: PhotosPickerItem?, top: Bool) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await vm.importLetterhead(data, top: top)
            } else {
                vm.errorMessage = "تعذر تحميل الصورة المختارة."
            }
        }
    }
}

private struct FramePage: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @State private var frameItem: PhotosPickerItem?

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hex: vm.report.frame.colorHex) }, set: { vm.report.frame.colorHex = UIColor($0).hexString })
    }

    var body: some View {
        Form {
            Section {
                A4PageView(page: 0, snapshot: vm.snapshot)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            ForEach(FrameCategory.allCases.filter { $0 != .all }) { category in
                Section(category.title) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            if category == .official { swatch(.none) }
                            ForEach(FrameStyle.allCases.filter { $0.category == category }) { swatch($0) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("اللون") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 10)], spacing: 10) {
                    ForEach(ThemeStore.palette, id: \.self) { hex in
                        Button {
                            vm.report.frame.colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary, lineWidth: vm.report.frame.colorHex == hex ? 2.5 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                ColorPicker("لون مخصص", selection: colorBinding, supportsOpacity: false)
            }

            Section {
                PhotosPicker(selection: $frameItem, matching: .images) {
                    Label(vm.report.frame.customFramePNG == nil ? "إطار من صورة" : "تغيير صورة الإطار", systemImage: "photo.on.rectangle")
                }
                if vm.report.frame.customFramePNG != nil {
                    Button("حذف صورة الإطار", role: .destructive) { vm.removeFrameImage() }
                }
            } footer: {
                Text("صورة إطار بحجم صفحة A4، تُزال خلفيتها البيضاء ليظهر النص فوقها.")
            }
        }
        .navigationTitle("الإطار")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: frameItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await vm.importFrameImage(data) }
                frameItem = nil
            }
        }
    }

    private func swatch(_ style: FrameStyle) -> some View {
        let selected = vm.report.frame.style == style
        return Button {
            vm.report.frame.style = style
        } label: {
            VStack(spacing: 4) {
                FrameSwatch(style: style, colorHex: vm.report.frame.colorHex, image: vm.images.frame)
                    .frame(width: 64, height: 64 / A4.aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(selected ? theme.accent : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                Text(style.title)
                    .font(.caption2)
                    .foregroundStyle(selected ? theme.accent : .primary)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AddresseePage: View {
    @ObservedObject var vm: ReportEditorViewModel

    var body: some View {
        Form {
            Section {
                Toggle("إظهار الموجَّه إليه", isOn: $vm.report.addressee.isEnabled)
                if vm.report.addressee.isEnabled {
                    TextField("المخاطَب (مثال: سعادة مدير إدارة المساجد بالحرث)", text: $vm.report.addressee.recipientTitle, axis: .vertical)
                    TextField("اسم المسؤول (مثال: الأستاذ/ ...)", text: $vm.report.addressee.recipientName)
                    FontSizeSlider(title: "حجم الخط", value: Binding(
                        get: { vm.report.addresseeFontSize },
                        set: { vm.report.addressee.fontSizeValue = $0 }
                    ), defaultValue: min(max(vm.report.textStyle.fontSize, 11), 24), numerals: vm.report.page.numerals, range: 9...30)
                    Toggle("عبارة التبجيل في يسار السطر", isOn: $vm.report.addressee.showHonorific)
                    if vm.report.addressee.showHonorific {
                        Picker("العبارة", selection: $vm.report.addressee.honorific) {
                            ForEach(AddresseeSettings.honorificSuggestions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Toggle("التحية", isOn: $vm.report.addressee.showGreeting)
                    if vm.report.addressee.showGreeting {
                        TextField("التحية", text: $vm.report.addressee.greeting, axis: .vertical)
                    }
                }
            } footer: {
                Text("يظهر أعلى الصفحة الأولى قبل نص التقرير.")
            }
        }
        .navigationTitle("الموجَّه إليه")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Moves something up / down in 2-point steps or with a slider.
struct VerticalPositionControl: View {
    @Binding var offset: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text("الموضع").font(.subheadline)
            Spacer()
            Button { offset = max(offset - 2, range.lowerBound) } label: { Image(systemName: "chevron.up").frame(width: 30, height: 30) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            Button { offset = min(offset + 2, range.upperBound) } label: { Image(systemName: "chevron.down").frame(width: 30, height: 30) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            if offset != 0 {
                Button { offset = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
            }
        }
    }
}
