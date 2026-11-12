import SwiftUI
import UIKit

/// Speech-to-text sheet: live Arabic transcript, inserted at the cursor.
struct DictationSheet: View {
    let onInsert: (String) -> Void
    @EnvironmentObject private var theme: ThemeStore
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
                        .foregroundStyle(dictation.isRecording ? Color.red : theme.accent)
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

/// Font browser grouped by style, each row previewed in its own font.
struct FontPickerView: View {
    @Binding var selection: String
    @EnvironmentObject private var fonts: FontRegistry
    @Environment(\.dismiss) private var dismiss
    @State private var sample = "تقرير رسمي — بسم الله الرحمن الرحيم ١٢٣"

    var body: some View {
        List {
            Section {
                TextField("نص المعاينة", text: $sample)
            } header: {
                Text("نص المعاينة")
            } footer: {
                Text("\(ArabicFormat.number(fonts.fonts.count, .arabicIndic)) خطاً متاحاً. يمكنك استيراد خطوطك من «المكتبة ← الخطوط».")
            }

            ForEach(fonts.grouped, id: \.category) { group in
                Section(group.category.title) {
                    ForEach(group.fonts) { font in
                        Button {
                            selection = font.postScriptName
                            dismiss()
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(font.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(sample.isEmpty ? font.displayName : sample)
                                        .font(.custom(font.postScriptName, size: 21))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selection == font.postScriptName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("اختيار الخط")
        .navigationBarTitleDisplayMode(.inline)
    }
}
