import SwiftUI

/// Text & page formatting plus the tidy / proofread tools — one sheet instead of several.
struct FormatSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var fonts: FontRegistry
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spellcheck.live") private var liveSpellCheck = true
    @StateObject private var consent = AIConsentGate()

    @State private var message: String?
    @State private var proofreading = false
    @State private var progress = ""
    @State private var showAISettings = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("الخط") {
                    NavigationLink {
                        FontPickerView(selection: $vm.report.textStyle.fontName)
                    } label: {
                        LabeledContent("نوع الخط") {
                            Text(fonts.displayName(for: vm.report.textStyle.fontName)).lineLimit(1)
                        }
                    }
                    Stepper(value: $vm.report.textStyle.fontSize, in: 10...32, step: 1) {
                        LabeledContent("حجم الخط", value: ArabicFormat.number(Int(vm.report.textStyle.fontSize), vm.report.page.numerals))
                    }
                    Text("بسم الله الرحمن الرحيم")
                        .font(.custom(vm.report.textStyle.fontName, size: CGFloat(vm.report.textStyle.fontSize) + 2))
                        .frame(maxWidth: .infinity)
                }

                Section("الفقرات") {
                    Picker("المحاذاة", selection: $vm.report.textStyle.defaultAlignment) {
                        ForEach(ParagraphAlignment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("تباعد الأسطر", selection: $vm.report.textStyle.lineSpacing) {
                        ForEach(LineSpacing.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $vm.report.textStyle.paragraphSpacing, in: 0...30, step: 2) {
                        LabeledContent("بين الفقرات", value: ArabicFormat.number(Int(vm.report.textStyle.paragraphSpacing), vm.report.page.numerals))
                    }
                }

                Section("الصفحة") {
                    Picker("الهوامش", selection: $vm.report.page.margins) {
                        ForEach(PageMargins.allCases.filter { $0 != .compact || vm.report.page.margins == .compact }) { Text($0.title).tag($0) }
                    }
                    Toggle("رقم الصفحة أسفل الورقة", isOn: $vm.report.page.showPageNumbers)
                    if let lines = PageLayoutSpec.estimatedLines(for: vm.report) {
                        LabeledContent("أسطر الصفحة تقريباً", value: ArabicFormat.number(lines.other, vm.report.page.numerals))
                    }
                }

                Section {
                    Button {
                        let edits = vm.formatAllText()
                        message = edits == 0 ? "النص منسّق بالفعل ✓" : "تم إجراء \(ArabicFormat.number(edits, vm.report.page.numerals)) تعديلاً ✓"
                    } label: {
                        Label("تنسيق المسافات وعلامات الترقيم", systemImage: "wand.and.stars")
                    }
                    Button {
                        consent.run { proofread() }
                    } label: {
                        HStack {
                            Label("تصحيح الإملاء والنحو (ذكاء اصطناعي)", systemImage: "checkmark.seal")
                            if proofreading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(proofreading || !AISettings.hasKey)
                    if proofreading {
                        Text(progress).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !AISettings.hasKey {
                        Button("إضافة مفتاح Claude لتفعيل التصحيح") { showAISettings = true }
                            .font(.footnote)
                    }
                    if let message {
                        Text(message).font(.footnote)
                    }
                    if let title = vm.undoTitle {
                        Button("تراجع عن «\(title)»", role: .destructive) {
                            vm.undo()
                            message = "تم التراجع."
                        }
                    }
                    Toggle("تنسيق تلقائي عند التصدير", isOn: $vm.report.autoFormat)
                    Toggle("إظهار الأخطاء الإملائية أثناء الكتابة", isOn: $liveSpellCheck)
                } header: {
                    Text("أدوات")
                } footer: {
                    Text("التنسيق يحافظ على العريض والتسطير والمحاذاة. التصحيح يغيّر الكلمات الخاطئة فقط في كل الصفحات.")
                }
            }
            .navigationTitle("التنسيق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showAISettings) {
                NavigationStack { AISettingsView() }
            }
            .aiConsentAlert(consent)
            .onDisappear { task?.cancel() }
        }
    }

    private func proofread() {
        proofreading = true
        message = nil
        let numerals = vm.report.page.numerals
        task = Task {
            do {
                let changes = try await vm.proofreadWithAI { page, total in
                    progress = "جارٍ تدقيق الصفحة \(ArabicFormat.number(page, numerals)) من \(ArabicFormat.number(total, numerals))…"
                }
                message = changes == 0 ? "لم يتم العثور على أخطاء ✓" : "تم تصحيح \(ArabicFormat.number(changes, numerals)) كلمة ✓"
            } catch is CancellationError {
                message = "تم الإيقاف."
            } catch {
                message = "❌ " + error.localizedDescription
            }
            proofreading = false
        }
    }
}
