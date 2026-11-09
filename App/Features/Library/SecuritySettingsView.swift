import SwiftUI

/// Security & privacy: app lock, how data is protected, AI consent, policy and licenses.
struct SecuritySettingsView: View {
    @EnvironmentObject private var lock: AppLock
    @AppStorage(AISettings.consentKey) private var aiConsent = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { lock.isEnabled },
                    set: { value in Task { await lock.setEnabled(value) } }
                )) {
                    Label("قفل التطبيق بـ \(lock.methodName)", systemImage: lock.methodIcon)
                }
                if let message = lock.message {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("القفل")
            } footer: {
                Text("يُطلب التحقق عند فتح التطبيق وعند الرجوع إليه. ويُخفى محتوى التقارير دائماً في شاشة تبديل التطبيقات.")
            }

            Section("حماية بياناتك") {
                infoRow("lock.doc", "التقارير والقوالب والتوقيعات مشفّرة على جهازك (AES-256)، ومفتاح التشفير في سلسلة المفاتيح.")
                infoRow("folder.badge.minus", "ملفات التطبيق مخفية عن تطبيق «الملفات» وعن الكمبيوتر عند توصيل الجوال.")
                infoRow("icloud.slash", "لا يوجد خادم: لا تُرسل تقاريرك لأي مكان، ولا يوجد تتبّع أو إعلانات.")
                infoRow("trash", "ملفات PDF والنسخ الاحتياطية المؤقتة تُحذف تلقائياً بعد المشاركة.")
                infoRow("key", "النسخ الاحتياطية مشفّرة بكلمة مرور تختارها أنت.")
            }

            Section {
                Toggle("السماح بإرسال النص لخدمة Claude", isOn: $aiConsent)
            } header: {
                Text("الذكاء الاصطناعي")
            } footer: {
                Text("عند استخدام مزايا الذكاء الاصطناعي فقط، يُرسل النص المطلوب معالجته إلى خدمة Claude من Anthropic عبر اتصال مشفّر. إيقاف الخيار يمنع أي إرسال.")
            }

            Section {
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("سياسة الخصوصية", systemImage: "hand.raised")
                }
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("تراخيص الخطوط", systemImage: "doc.plaintext")
                }
            }
        }
        .navigationTitle("الأمان والخصوصية")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}

/// Open-source font licenses (SIL OFL) bundled with the app.
struct LicensesView: View {
    private struct License: Identifiable {
        let id: String
        let name: String
        let url: URL
    }

    private var licenses: [License] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []
        return urls
            .filter { $0.lastPathComponent.hasSuffix("-OFL.txt") }
            .map { url in
                let name = url.lastPathComponent.replacingOccurrences(of: "-OFL.txt", with: "")
                return License(id: name, name: name, url: url)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                ForEach(licenses) { license in
                    NavigationLink(license.name) {
                        ScrollView {
                            Text((try? String(contentsOf: license.url, encoding: .utf8)) ?? "")
                                .font(.system(.footnote, design: .monospaced))
                                .environment(\.layoutDirection, .leftToRight)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle(license.name)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
            } footer: {
                Text("الخطوط العربية في التطبيق مفتوحة المصدر بموجب رخصة SIL Open Font License 1.1، ونصوص الرخص مرفقة هنا كما تشترط.")
            }
        }
        .navigationTitle("تراخيص الخطوط")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Asks for explicit permission the first time text would be sent to the AI service.
@MainActor
final class AIConsentGate: ObservableObject {
    @Published var isAsking = false
    private var pending: (() -> Void)?

    func run(_ action: @escaping () -> Void) {
        if AISettings.hasConsent {
            action()
        } else {
            pending = action
            isAsking = true
        }
    }

    func accept() {
        AISettings.hasConsent = true
        let action = pending
        pending = nil
        action?()
    }

    func decline() {
        pending = nil
    }
}

extension View {
    func aiConsentAlert(_ gate: AIConsentGate) -> some View {
        alert("إرسال النص للذكاء الاصطناعي", isPresented: Binding(
            get: { gate.isAsking },
            set: { gate.isAsking = $0 }
        )) {
            Button("موافق") { gate.accept() }
            Button("لا", role: .cancel) { gate.decline() }
        } message: {
            Text("لتنفيذ هذا الطلب سيُرسل النص المحدد (وعنوان التقرير واسم الجهة) إلى خدمة Claude من Anthropic عبر اتصال مشفّر. لا يُرسل أي شيء آخر، ويمكنك إيقاف ذلك من «الأمان والخصوصية». هل توافق؟")
        }
    }
}
