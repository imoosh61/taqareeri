import PhotosUI
import SwiftUI
import UIKit

/// Step 2: decoration library for the page borders, plus user-imported frame artwork.
struct FrameGalleryView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @State private var category: FrameCategory = .all
    @State private var frameItem: PhotosPickerItem?
    @State private var zoomPage: PageRef?

    private var styles: [FrameStyle] {
        let all = FrameStyle.allCases.filter { $0 != .customImage || vm.report.frame.customFramePNG != nil }
        guard category != .all else { return all }
        return all.filter { $0 == .none || $0.category == category }
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
                    .onTapGesture { zoomPage = PageRef(id: vm.firstBodyPhysicalPage) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FrameCategory.allCases) { item in
                            Button {
                                category = item
                            } label: {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(category == item ? theme.accent : Color(.secondarySystemBackground))
                                    )
                                    .foregroundStyle(category == item ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 16) {
                    ForEach(styles) { style in
                        swatchButton(style)
                    }
                }

                customFrameSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("لون الإطار والفواصل").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 10)], spacing: 10) {
                        ForEach(ThemeStore.palette, id: \.self) { hex in
                            Button {
                                vm.report.frame.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: vm.report.frame.colorHex == hex ? 2.5 : 0)
                                            .padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ColorPicker("لون مخصص", selection: colorBinding, supportsOpacity: false)
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
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .onChange(of: frameItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await vm.importFrameImage(data)
                } else {
                    vm.errorMessage = "تعذر تحميل الصورة المختارة."
                }
                frameItem = nil
            }
        }
    }

    private func swatchButton(_ style: FrameStyle) -> some View {
        let selected = vm.report.frame.style == style
        return Button {
            vm.report.frame.style = style
        } label: {
            VStack(spacing: 6) {
                FrameSwatch(style: style, colorHex: vm.report.frame.colorHex, image: vm.images.frame)
                    .aspectRatio(A4.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(selected ? theme.accent : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                Text(style.title)
                    .font(.caption)
                    .foregroundStyle(selected ? theme.accent : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customFrameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("إطار خاص من صورة").font(.headline)
            Text("ارفع صورة إطار بحجم صفحة A4 (مثل إطار جهتك الرسمي). تُزال الخلفية البيضاء تلقائياً ليظهر النص فوقه.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                PhotosPicker(selection: $frameItem, matching: .images) {
                    Label(vm.report.frame.customFramePNG == nil ? "رفع إطار" : "تغيير الإطار", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                if vm.report.frame.customFramePNG != nil {
                    Button(role: .destructive) {
                        vm.removeFrameImage()
                    } label: {
                        Label("حذف", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                if vm.isProcessingImage {
                    ProgressView().padding(.horizontal, 6)
                }
            }
        }
    }
}
