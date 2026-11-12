import SwiftUI
import UIKit

/// Font size slider with live value and a reset-to-default button.
struct FontSizeSlider: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let numerals: NumeralStyle
    var range: ClosedRange<Double> = 7...20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(ArabicFormat.number(Int(value.rounded()), numerals))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if value != defaultValue {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("الحجم الافتراضي")
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: $value, in: range, step: 0.5)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Moves a header block left / right and sets its text alignment.
struct HorizontalPositionControl: View {
    let title: String
    @Binding var offset: Double
    @Binding var alignment: ParagraphAlignment

    private let alignments: [ParagraphAlignment] = [.left, .center, .right]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if offset != 0 {
                    Button {
                        offset = 0
                    } label: {
                        Label("الوضع الأصلي", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                nudge("chevron.left") { offset = max(offset - 2, -160) }
                Text("يسار").font(.caption).foregroundStyle(.secondary)
                Slider(value: $offset, in: -160...160, step: 1)
                Text("يمين").font(.caption).foregroundStyle(.secondary)
                nudge("chevron.right") { offset = min(offset + 2, 160) }
            }
            .environment(\.layoutDirection, .leftToRight)

            Picker("محاذاة النص", selection: $alignment) {
                ForEach(alignments) { item in
                    Image(systemName: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 4)
    }

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}

/// The top strip of a page (letterhead area) so header changes are visible while editing below.
struct HeaderStripPreview: View {
    let snapshot: DocumentSnapshot
    var page = 0

    var body: some View {
        let spec = snapshot.spec
        let visible = max(spec.headerRect(bodyPage: page).maxY, spec.topLetterheadRect(bodyPage: page)?.maxY ?? 0) + 10
        GeometryReader { proxy in
            let width = proxy.size.width
            A4PageView(page: page, snapshot: snapshot)
                .frame(width: width, height: width / A4.aspectRatio)
                .frame(width: width, height: visible * width / A4.size.width, alignment: .top)
                .clipped()
        }
        .aspectRatio(A4.size.width / visible, contentMode: .fit)
    }
}

