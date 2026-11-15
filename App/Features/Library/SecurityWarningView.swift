import SwiftUI

/// Shown when the integrity checks fail: a warning the user can dismiss, or a block in strict mode.
struct SecurityWarningView: View {
    @ObservedObject var guardState: GuardState

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text("بيئة تشغيل غير آمنة")
                    .font(.title2.weight(.bold))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(guardState.result.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "xmark.octagon")
                    }
                }
                .font(.subheadline)
                Text(guardState.isStrict
                     ? "التطبيق متوقف لحماية تقاريرك وتوقيعاتك. شغّله على جهاز غير معدَّل."
                     : "قد يتمكن غيرك من قراءة تقاريرك وتوقيعاتك على هذا الجهاز. يُنصح بعدم حفظ معلومات سرية عليه.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !guardState.isStrict {
                    Button {
                        guardState.acknowledged = true
                    } label: {
                        Text("متابعة على مسؤوليتي")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top, 8)
                }
            }
            .padding(32)
        }
    }
}
