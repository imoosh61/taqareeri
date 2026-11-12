import SwiftUI

/// Saved phrases (built-in + the user's own), kept on this device.
@MainActor
final class PhraseStore: ObservableObject {
    static let defaults = [
        "السلام عليكم ورحمة الله وبركاته، وبعد:",
        "بالإشارة إلى ما ورد إلينا بخصوص",
        "نفيد سعادتكم بأنه",
        "نرفع لسعادتكم التقرير المرفق بخصوص",
        "نأمل الاطلاع والتوجيه بما ترونه مناسباً.",
        "وتقبلوا وافر التحية والتقدير.",
        "شاكرين لكم حسن تعاونكم.",
        "والله يحفظكم ويرعاكم."
    ]

    private static let key = "phrases.list"

    @Published var phrases: [String] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            phrases = saved
        } else {
            phrases = Self.defaults
        }
    }

    func add(_ phrase: String) {
        let text = phrase.trimmed
        guard !text.isEmpty, !phrases.contains(text) else { return }
        phrases.append(text)
    }

    func resetToDefaults() {
        phrases = Self.defaults
    }

    private func save() {
        if let data = try? JSONEncoder().encode(phrases) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Tap a phrase to insert it where you are writing.
struct PhrasesSheet: View {
    let onInsert: (String) -> Void
    @StateObject private var store = PhraseStore()
    @Environment(\.dismiss) private var dismiss
    @State private var newPhrase = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.phrases, id: \.self) { phrase in
                        Button {
                            onInsert(phrase)
                            dismiss()
                        } label: {
                            Text(phrase)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onDelete { store.phrases.remove(atOffsets: $0) }
                    .onMove { store.phrases.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("اضغط العبارة لإدراجها مكان المؤشر. اسحبها لليسار لحذفها.")
                }

                Section("إضافة عبارة") {
                    TextField("اكتب عبارة تستخدمها كثيراً", text: $newPhrase, axis: .vertical)
                        .lineLimit(1...4)
                    Button {
                        store.add(newPhrase)
                        newPhrase = ""
                    } label: {
                        Label("حفظ العبارة", systemImage: "plus.circle")
                    }
                    .disabled(newPhrase.trimmed.isEmpty)
                }

                Section {
                    Button("استعادة العبارات الافتراضية") { store.resetToDefaults() }
                }
            }
            .navigationTitle("عبارات جاهزة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
    }
}
