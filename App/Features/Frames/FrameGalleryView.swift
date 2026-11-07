import SwiftUI
import UIKit

/// Step 2: decoration library for the page borders.
struct FrameGalleryView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var category: FrameCategory = .all

    private var styles: [FrameStyle] {
        guard category != .all else { return FrameStyle.allCases }
        return FrameStyle.allCases.filter { $0 == .none || $0.category == category }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: vm.report.frame.colorHex) },
            set: { vm.report.frame.colorHex = UIColor($0).hexString }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                A4PageView(page: vm.firstBodyPhysicalPage, context: vm.renderContext)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)

                Picker("التصنيف", selection: $category) {
                    ForEach(FrameCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 16) {
                    ForEach(styles) { style in
                        let selected = vm.report.frame.style == style
                        Button {
                            vm.report.frame.style = style
                        } label: {
                            VStack(spacing: 6) {
                                FrameSwatch(style: style, colorHex: vm.report.frame.colorHex)
                                    .aspectRatio(A4.aspectRatio, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(selected ? Theme.accent : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                Text(style.title)
                                    .font(.caption)
                                    .foregroundStyle(selected ? Theme.accent : .primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("لون الإطار والفواصل").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(Theme.framePresets, id: \.self) { hex in
                            Button {
                                vm.report.frame.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: vm.report.frame.colorHex == hex ? 2.5 : 0)
                                            .padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("لون مخصص", selection: colorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                }

                Toggle("تطبيق الإطار على صفحة الغلاف", isOn: $vm.report.frame.applyToCover)
                    .disabled(!vm.report.cover.isEnabled)
                if !vm.report.cover.isEnabled {
                    Text("فعّل صفحة الغلاف من تبويب «الترويسة» للتحكم بإطارها.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
