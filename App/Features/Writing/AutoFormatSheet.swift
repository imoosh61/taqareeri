import SwiftUI

/// One place for automatic tidying and spelling correction, each with undo.
struct AutoFormatSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spellcheck.live") private var liveSpellCheck = true

    @State private var formatMessage: String?
    @State private var aiMessage: String?
    @State private var aiWorking = false
    @State private var aiProgress = ""
    @State private var showAISettings = false
    @State private var aiTask: Task<Void, Never>?
    @StateObject private var consent = AIConsentGate()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        let edits = vm.formatText()
                        formatMessage = edits == 0
                            ? "النص منسّق بالفعل ✓"
                            : "تم إجراء \(ArabicFormat.number(edits, vm.report.page.numerals)) تعديلاً ✓"
                    } label: {
                        Label("تنسيق النص الآن", systemImage: "wand.and.stars")
                    }
                    if let formatMessage {
                        Text(formatMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("تنسيق تلقائي قبل المعاينة والتصدير", isOn: $vm.report.autoFormat)
                } header: {
                    Text("التنسيق")
                } footer: {
                    Text("يزيل المسافات الزائدة، ويضبط المسافات حول الفواصل والأقواس، ويحوّل , ; ? إلى ، ؛ ؟ ويُلصق واو العطف بالكلمة. يحافظ على العريض والتسطير والمحاذاة.")
                }

                Section {
                    Toggle("إظهار الأخطاء الإملائية أثناء الكتابة", isOn: $liveSpellCheck)

                    Button {
                        consent.run { runProofread() }
                    } label: {
                        HStack {
                            Label("تصحيح الأخطاء الإملائية والنحوية", systemImage: "checkmark.seal")
                            if aiWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(aiWorking || !AISettings.hasKey || vm.bodyText.string.trimmed.isEmpty)

                    if aiWorking {
                        Text(aiProgress).font(.footnote).foregroundStyle(.secondary)
                        Button("إيقاف", role: .destructive) { aiTask?.cancel() }
                    }
                    if let aiMessage {
                        Text(aiMessage).font(.footnote)
                    }
                    if !AISettings.hasKey {
                        Button("إضافة مفتاح Claude API لتفعيل التصحيح") { showAISettings = true }
                    }
                } header: {
                    Text("التدقيق الإملائي")
                } footer: {
                    Text("الخطوط الحمراء أثناء الكتابة من تدقيق iOS حسب لغة لوحة المفاتيح. التصحيح الكامل يتم بالذكاء الاصطناعي ويغيّر الكلمات الخاطئة فقط مع الحفاظ على التنسيق وفواصل الصفحات.")
                }

                if vm.canUndoTextChange {
                    Section {
                        Button(role: .destructive) {
                            vm.undoTextChange()
                            formatMessage = nil
                            aiMessage = "تم التراجع عن آخر تعديل."
                        } label: {
                            Label("تراجع عن آخر تنسيق أو تصحيح", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle("تنسيق وتدقيق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showAISettings) {
                NavigationStack { AISettingsView() }
            }
            .onDisappear { aiTask?.cancel() }
            .aiConsentAlert(consent)
        }
    }

    private func runProofread() {
        aiMessage = nil
        aiWorking = true
        aiProgress = "جارٍ التدقيق…"
        let numerals = vm.report.page.numerals
        aiTask = Task {
            do {
                let changes = try await vm.proofreadWithAI { part, total in
                    aiProgress = total > 1
                        ? "جارٍ تدقيق الجزء \(ArabicFormat.number(part, numerals)) من \(ArabicFormat.number(total, numerals))…"
                        : "جارٍ التدقيق…"
                }
                aiMessage = changes == 0
                    ? "لم يتم العثور على أخطاء ✓"
                    : "تم تصحيح \(ArabicFormat.number(changes, numerals)) كلمة ✓"
            } catch is CancellationError {
                aiMessage = "تم الإيقاف."
            } catch {
                aiMessage = "❌ " + error.localizedDescription
            }
            aiWorking = false
        }
    }
}
