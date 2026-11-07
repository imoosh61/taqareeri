import SwiftUI
import UIKit

/// AI writing assistant: drafts from bullet points, or rewrites the selection / whole report.
struct AIAssistantSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var task: AIWritingTask = .draft
    @State private var scope: Scope = .selection
    @State private var notes = ""
    @State private var result = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var requestTask: Task<Void, Never>?

    enum Scope: String, CaseIterable, Identifiable {
        case selection, all
        var id: String { rawValue }
        var title: String { self == .selection ? "النص المحدد" : "التقرير كاملاً" }
    }

    private var hasSelection: Bool { vm.richText.hasSelection }

    private var sourceText: String {
        if task == .draft { return notes }
        if scope == .selection && hasSelection { return vm.richText.selectedText }
        return vm.bodyText.string.replacingOccurrences(of: BodyDocument.pageBreak, with: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                if !AISettings.hasKey {
                    Section {
                        Label("لم يُضف مفتاح Claude API بعد.", systemImage: "key")
                        Button("إضافة المفتاح الآن") { showSettings = true }
                    }
                }

                Section("المهمة") {
                    Picker("المهمة", selection: $task) {
                        ForEach(AIWritingTask.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if task == .draft {
                    Section {
                        TextField("مثال: تقرير عن ورشة عمل السلامة المهنية يوم الأحد، حضرها ٢٥ موظفاً، أبرز التوصيات…", text: $notes, axis: .vertical)
                            .lineLimit(4...10)
                    } header: {
                        Text("النقاط والمعطيات")
                    } footer: {
                        Text("اكتب ما تعرفه باختصار، وسيصوغه الذكاء الاصطناعي تقريراً رسمياً.")
                    }
                } else {
                    Section {
                        Picker("النطاق", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if scope == .selection && !hasSelection {
                            Text("لا يوجد نص محدد، سيُستخدم التقرير كاملاً.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("على أي نص؟")
                    }
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                                Text("جارٍ الكتابة…").padding(.leading, 6)
                            } else {
                                Label("توليد", systemImage: "sparkles")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isWorking || sourceText.trimmed.isEmpty || !AISettings.hasKey)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !result.isEmpty {
                    Section("النتيجة (يمكنك تعديلها)") {
                        TextEditor(text: $result)
                            .frame(minHeight: 200)
                    }
                    Section {
                        resultActions
                    }
                }

                Section {
                    Text("يُرسَل النص إلى خدمة Claude لمعالجته عند الضغط على «توليد» فقط. راجع سياسة جهتك قبل إرسال معلومات حساسة.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("مساعد الكتابة الذكي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") {
                        requestTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { AISettingsView() }
            }
            .onAppear {
                scope = hasSelection ? .selection : .all
                if !vm.bodyText.string.trimmed.isEmpty && task == .draft && hasSelection {
                    task = .formalize
                }
            }
            .onDisappear { requestTask?.cancel() }
        }
    }

    @ViewBuilder
    private var resultActions: some View {
        if task == .title {
            Button {
                vm.report.title = result.trimmed
                dismiss()
            } label: {
                Label("تعيين كعنوان للتقرير", systemImage: "checkmark.circle")
            }
        } else {
            if task != .draft && scope == .selection && hasSelection {
                Button {
                    vm.richText.replaceSelection(with: result)
                    dismiss()
                } label: {
                    Label("استبدال النص المحدد", systemImage: "arrow.left.arrow.right")
                }
            }
            if task != .draft && !(scope == .selection && hasSelection) {
                Button {
                    vm.richText.replaceAll(with: result)
                    dismiss()
                } label: {
                    Label("استبدال التقرير كاملاً", systemImage: "arrow.left.arrow.right")
                }
            }
            Button {
                vm.richText.insertText((vm.bodyText.length > 0 ? "\n" : "") + result)
                dismiss()
            } label: {
                Label("إدراج عند المؤشر", systemImage: "text.insert")
            }
        }
        Button {
            UIPasteboard.general.string = result
        } label: {
            Label("نسخ", systemImage: "doc.on.doc")
        }
    }

    private func generate() {
        let input = sourceText
        let context = AIReportContext(
            title: vm.report.title,
            ministry: vm.report.header.ministry,
            administration: vm.report.header.generalAdministration,
            department: vm.report.header.department
        )
        let selectedTask = task
        errorMessage = nil
        isWorking = true
        requestTask?.cancel()
        requestTask = Task {
            do {
                let text = try await AIWritingService().run(task: selectedTask, input: input, context: context)
                if !Task.isCancelled { result = text }
            } catch is CancellationError {
                // Sheet closed: nothing to show.
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            isWorking = false
        }
    }
}

/// API key (Keychain) and model choice.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = AISettings.apiKey ?? ""
    @State private var model = AISettings.model
    @State private var testState: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                SecureField("sk-ant-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("الحصول على مفتاح من Claude Console", systemImage: "arrow.up.forward.square")
                }
            } header: {
                Text("مفتاح Claude API")
            } footer: {
                Text("يُحفظ المفتاح مشفّراً في سلسلة المفاتيح (Keychain) على هذا الجهاز فقط، ولا يُضمَّن في التطبيق.")
            }

            Section("النموذج") {
                Picker("النموذج", selection: $model) {
                    ForEach(AIModelOption.allCases) { Text($0.title).tag($0.rawValue) }
                    if AIModelOption(rawValue: model) == nil {
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                TextField("أو اكتب معرّف نموذج آخر", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }

            Section {
                Button {
                    save()
                    test()
                } label: {
                    HStack {
                        Text("حفظ واختبار الاتصال")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(apiKey.trimmed.isEmpty || testing)
                if let testState {
                    Text(testState).font(.footnote)
                }
                if AISettings.hasKey {
                    Button("حذف المفتاح", role: .destructive) {
                        AISettings.apiKey = nil
                        apiKey = ""
                        testState = nil
                    }
                }
            }
        }
        .navigationTitle("الذكاء الاصطناعي")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    save()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        AISettings.apiKey = apiKey.trimmed
        AISettings.model = model.trimmed.isEmpty ? AIModelOption.sonnet.rawValue : model
    }

    private func test() {
        testing = true
        testState = nil
        Task {
            do {
                let reply = try await AIWritingService().run(
                    task: .title,
                    input: "اختبار اتصال: تقرير عن اجتماع قسم الموارد البشرية.",
                    context: AIReportContext(title: "", ministry: "", administration: "", department: "")
                )
                testState = "✅ الاتصال يعمل. مثال: \(reply)"
            } catch {
                testState = "❌ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
