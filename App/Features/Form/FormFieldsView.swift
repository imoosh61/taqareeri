import SwiftUI

/// Form report fields: title bar, labelled boxes (width & height), templates.
struct FormFieldsView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var zoomPage: PageRef?
    @State private var pendingTemplate: FormTemplate?

    var body: some View {
        Form {
            Section {
                A4PageView(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .onTapGesture { zoomPage = PageRef(id: vm.firstBodyPhysicalPage) }
            }
            .listRowBackground(Color.clear)

            Section("العنوان") {
                TextField("عنوان النموذج (مثل: إنجاز الدروس)", text: $vm.report.title)
                Toggle("شريط العنوان الملوّن", isOn: $vm.report.form.showTitleBar)
                FontSizeSlider(
                    title: "حجم خط البيانات",
                    value: $vm.report.form.valueFontSize,
                    defaultValue: 13,
                    numerals: vm.report.page.numerals,
                    range: 9...18
                )
            }

            ForEach(Array(vm.report.form.fields.enumerated()), id: \.element.id) { index, field in
                fieldSection(index: index, field: field)
            }

            Section {
                Button {
                    vm.addFormField()
                } label: {
                    Label("إضافة حقل", systemImage: "plus.rectangle")
                }
                Menu {
                    ForEach([FormTemplate.blank] + FormTemplate.all) { template in
                        Button(template.title) { pendingTemplate = template }
                    }
                } label: {
                    Label("استبدال الحقول بقالب جاهز", systemImage: "square.on.square")
                }
            } footer: {
                Text("الحقول تُرتَّب من اليمين: حقلان «نصف» أو ثلاثة «ثلث» في السطر الواحد.")
            }
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .confirmationDialog(
            "استبدال الحقول بقالب «\(pendingTemplate?.title ?? "")»؟",
            isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
            titleVisibility: .visible
        ) {
            Button("استبدال", role: .destructive) {
                if let template = pendingTemplate { vm.applyFormTemplate(template) }
                pendingTemplate = nil
            }
            Button("إلغاء", role: .cancel) { pendingTemplate = nil }
        } message: {
            Text("ستُحذف قيم الحقول الحالية.")
        }
    }

    private func fieldSection(index: Int, field: FormField) -> some View {
        Section {
            TextField("اسم الحقل", text: binding(field.id, \.label))
                .font(.subheadline.weight(.semibold))
            TextField("القيمة", text: binding(field.id, \.value), axis: .vertical)
                .lineLimit(1...8)
            Picker("العرض", selection: binding(field.id, \.width)) {
                ForEach(FieldWidth.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper(value: binding(field.id, \.lines), in: 1...14) {
                HStack {
                    Text("الارتفاع (أسطر)")
                    Spacer()
                    Text(ArabicFormat.number(field.lines, vm.report.page.numerals))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    vm.moveFormField(field.id, by: -1)
                } label: {
                    Label("تقديم", systemImage: "arrow.up")
                }
                .disabled(index == 0)
                Spacer()
                Button {
                    vm.moveFormField(field.id, by: 1)
                } label: {
                    Label("تأخير", systemImage: "arrow.down")
                }
                .disabled(index == vm.report.form.fields.count - 1)
                Spacer()
                Button(role: .destructive) {
                    vm.removeFormField(field.id)
                } label: {
                    Label("حذف", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        } header: {
            Text(field.label.trimmed.isEmpty ? "حقل \(ArabicFormat.number(index + 1, vm.report.page.numerals))" : field.label)
        }
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<FormField, Value>) -> Binding<Value> {
        Binding(
            get: {
                let field = vm.report.form.fields.first { $0.id == id } ?? FormField(label: "")
                return field[keyPath: keyPath]
            },
            set: { value in
                if let index = vm.report.form.fields.firstIndex(where: { $0.id == id }) {
                    vm.report.form.fields[index][keyPath: keyPath] = value
                }
            }
        )
    }
}

/// Choose a ready-made form when creating a new evidence report.
struct FormTemplatePicker: View {
    let onPick: (FormTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FormTemplate.all) { template in
                        row(template)
                    }
                } header: {
                    Text("قوالب جاهزة للمعلمين")
                } footer: {
                    Text("الأهداف والوصف مكتوبة مسبقاً، عدّل ما يلزم فقط.")
                }
                Section {
                    row(FormTemplate.blank)
                }
            }
            .navigationTitle("نموذج شواهد جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
    }

    private func row(_ template: FormTemplate) -> some View {
        Button {
            dismiss()
            onPick(template)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).font(.headline).foregroundStyle(.primary)
                    Text(template.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
