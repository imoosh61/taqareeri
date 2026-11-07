import SwiftUI
import UIKit

/// Step 3: the editor with formatting tools and a live A4 preview of the page under the cursor.
struct WritingView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var showTextSettings = false
    @State private var showDictation = false
    @State private var showSections = false
    @State private var zoomPage: PageRef?
    @State private var keyboardVisible = false
    @State private var previewExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            FormattingToolbar(
                vm: vm,
                onShowSettings: { showTextSettings = true },
                onDictation: { showDictation = true },
                onSections: { showSections = true }
            )

            RichTextEditor(
                controller: vm.richText,
                content: vm.bodyText,
                revision: vm.bodyRevision,
                typingAttributes: vm.typingAttributes
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            livePreview
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showTextSettings) {
            TextSettingsSheet(vm: vm)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDictation) {
            DictationSheet { text in vm.richText.insertText(text) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSections) {
            SectionsOrderSheet(vm: vm)
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private var livePreview: some View {
        let page = vm.cursorPhysicalPage
        return VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { previewExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "doc.richtext")
                    Text("معاينة A4 مباشرة")
                    Spacer()
                    Text(vm.pageLabel(forPhysicalPage: page))
                        .foregroundStyle(.secondary)
                    Image(systemName: previewExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            if previewExpanded {
                A4PageView(page: page, context: vm.renderContext)
                    .frame(height: keyboardVisible ? 120 : 230)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { zoomPage = PageRef(id: page) }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct FormattingToolbar: View {
    @ObservedObject var vm: ReportEditorViewModel
    let onShowSettings: () -> Void
    let onDictation: () -> Void
    let onSections: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tool("textformat", "إعدادات الخط والفقرات", action: onShowSettings)
                divider
                tool("bold", "عريض") { vm.richText.toggleBold() }
                tool("underline", "تسطير") { vm.richText.toggleUnderline() }
                tool("textformat.size.larger", "تكبير النص المحدد") { vm.richText.adjustSelectionSize(by: 1) }
                tool("textformat.size.smaller", "تصغير النص المحدد") { vm.richText.adjustSelectionSize(by: -1) }
                divider
                ForEach(ParagraphAlignment.allCases) { alignment in
                    tool(alignment.systemImage, "محاذاة \(alignment.title)", fixedDirection: true) {
                        vm.richText.setAlignment(alignment)
                    }
                }
                divider
                tool("doc.badge.plus", "فاصل صفحة") { vm.richText.insertPageBreak() }
                tool("arrow.up.arrow.down", "ترتيب الأقسام", action: onSections)
                tool("mic.fill", "إملاء صوتي", action: onDictation)
                tool("keyboard.chevron.compact.down", "إخفاء لوحة المفاتيح") { KeyboardHelper.dismiss() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var divider: some View {
        Divider().frame(height: 24)
    }

    private func tool(_ icon: String, _ label: String, fixedDirection: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 32)
                .environment(\.layoutDirection, fixedDirection ? .leftToRight : .rightToLeft)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}

/// Global typography & page numbering.
struct TextSettingsSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var fonts: FontRegistry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("الخط") {
                    Picker("نوع الخط", selection: $vm.report.textStyle.fontName) {
                        ForEach(fonts.fonts) { font in
                            Text(font.displayName)
                                .font(.custom(font.postScriptName, size: 17))
                                .tag(font.postScriptName)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Stepper(value: $vm.report.textStyle.fontSize, in: 10...32, step: 1) {
                        HStack {
                            Text("حجم الخط")
                            Spacer()
                            Text(ArabicFormat.number(Int(vm.report.textStyle.fontSize), vm.report.page.numerals))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("نص تجريبي: بسم الله الرحمن الرحيم")
                        .font(.custom(vm.report.textStyle.fontName, size: CGFloat(vm.report.textStyle.fontSize) + 2))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }

                Section {
                    Picker("المحاذاة", selection: $vm.report.textStyle.defaultAlignment) {
                        ForEach(ParagraphAlignment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $vm.report.textStyle.lineHeightMultiple, in: 1.0...2.4, step: 0.1) {
                        HStack {
                            Text("تباعد الأسطر")
                            Spacer()
                            Text(String(format: "%.1f", vm.report.textStyle.lineHeightMultiple))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $vm.report.textStyle.paragraphSpacing, in: 0...30, step: 2) {
                        HStack {
                            Text("المسافة بين الفقرات")
                            Spacer()
                            Text(ArabicFormat.number(Int(vm.report.textStyle.paragraphSpacing), vm.report.page.numerals))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("الفقرات")
                } footer: {
                    Text("تغيير المحاذاة هنا يُطبَّق على جميع الفقرات. لمحاذاة فقرة واحدة استخدم أزرار شريط الأدوات.")
                }

                Section("ترقيم الصفحات") {
                    Toggle("إظهار رقم الصفحة أسفل الورقة", isOn: $vm.report.page.showPageNumbers)
                }
            }
            .navigationTitle("إعدادات النص")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}

/// Speech-to-text sheet: live Arabic transcript, inserted at the cursor.
struct DictationSheet: View {
    let onInsert: (String) -> Void
    @StateObject private var dictation = SpeechDictation()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ScrollView {
                    Text(dictation.transcript.isEmpty ? "تحدّث الآن… سيظهر النص هنا." : dictation.transcript)
                        .font(.title3)
                        .foregroundStyle(dictation.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                statusView

                Button {
                    if dictation.isRecording {
                        dictation.stop()
                    } else {
                        Task { await dictation.start() }
                    }
                } label: {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 68))
                        .foregroundStyle(dictation.isRecording ? Color.red : Theme.accent)
                        .symbolEffect(.pulse, isActive: dictation.isRecording)
                }
                .accessibilityLabel(dictation.isRecording ? "إيقاف" : "بدء الإملاء")
            }
            .padding()
            .navigationTitle("الإملاء الصوتي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") {
                        dictation.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إدراج") {
                        dictation.stop()
                        let text = dictation.transcript.trimmed
                        if !text.isEmpty { onInsert(text + " ") }
                        dismiss()
                    }
                    .disabled(dictation.transcript.trimmed.isEmpty)
                }
            }
            .task { await dictation.start() }
            .onDisappear { dictation.stop() }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch dictation.status {
        case .preparing:
            ProgressView("جارٍ التحضير…")
        case .recording:
            Label("يتم الاستماع…", systemImage: "waveform")
                .foregroundStyle(.red)
        case .message(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .idle:
            Text("اضغط على الميكروفون للمتابعة.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Reorders the parts of the report separated by page breaks.
struct SectionsOrderSheet: View {
    @ObservedObject var vm: ReportEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [BodySection] = []

    var body: some View {
        NavigationStack {
            List {
                if items.count < 2 {
                    Text("أدرج «فاصل صفحة» من شريط الأدوات لتقسيم التقرير إلى أقسام، ثم رتّبها هنا بالسحب.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("القسم \(ArabicFormat.number(section.id + 1, vm.report.page.numerals))")
                            .font(.headline)
                        Text(section.preview.isEmpty ? "(فارغ)" : section.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ترتيب الأقسام")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تطبيق") {
                        vm.reorderSections(items.map(\.id))
                        dismiss()
                    }
                    .disabled(items.count < 2)
                }
            }
            .onAppear { items = vm.sections() }
        }
    }
}
