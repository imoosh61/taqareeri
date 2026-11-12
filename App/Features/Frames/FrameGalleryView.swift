import PhotosUI
import SwiftUI
import UIKit

/// Step 2: decoration library for the page borders, plus user-imported frame artwork.
struct FrameGalleryView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @EnvironmentObject private var theme: ThemeStore
    @State private var category: FrameCategory = .all
    @State private var frameItem: PhotosPickerItem?
    @State private var topLetterheadItem: PhotosPickerItem?
    @State private var bottomLetterheadItem: PhotosPickerItem?
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

                letterheadSection

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
        .onChange(of: topLetterheadItem) { _, item in
            loadLetterhead(item, top: true)
            topLetterheadItem = nil
        }
        .onChange(of: bottomLetterheadItem) { _, item in
            loadLetterhead(item, top: false)
            bottomLetterheadItem = nil
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

    // MARK: - Organisation letterhead ("ورق الجهة")

    private var letterheadSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ورق الجهة الرسمي").font(.headline)
                Text("ارفع صورة ترويسة الجهة (أعلى الصفحة) وصورة معلومات الاتصال (أسفل الصفحة)، فتُوضع تلقائياً ويبدأ النص بينهما.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            letterheadRow(
                title: "صورة أعلى الصفحة",
                icon: "rectangle.tophalf.inset.filled",
                data: vm.report.frame.letterheadTopPNG,
                selection: $topLetterheadItem,
                scale: $vm.report.frame.letterheadTopScale,
                offset: $vm.report.frame.letterheadTopOffset,
                offsetRange: FrameSettings.letterheadTopOffsetRange,
                top: true
            )

            letterheadRow(
                title: "صورة أسفل الصفحة",
                icon: "rectangle.bottomhalf.inset.filled",
                data: vm.report.frame.letterheadBottomPNG,
                selection: $bottomLetterheadItem,
                scale: $vm.report.frame.letterheadBottomScale,
                offset: $vm.report.frame.letterheadBottomOffset,
                offsetRange: FrameSettings.letterheadBottomOffsetRange,
                top: false
            )

            if vm.report.frame.hasLetterhead {
                Toggle("على كل الصفحات", isOn: $vm.report.frame.letterheadAllPages)
                Toggle("إظهار الشعار وبيانات الترويسة تحت الصورة", isOn: $vm.report.header.isEnabled)
                Text("عند الإيقاف تظهر في الصفحة الأولى فقط. احفظها ضمن قالب من تبويب «الترويسة» لتأتي جاهزة في كل تقرير جديد.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func letterheadRow(
        title: String,
        icon: String,
        data: Data?,
        selection: Binding<PhotosPickerItem?>,
        scale: Binding<Double>,
        offset: Binding<Double>,
        offsetRange: ClosedRange<Double>,
        top: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))

            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 70)
                    .padding(6)
                    .background(CheckerboardBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Text("العرض").font(.caption).foregroundStyle(.secondary)
                    Slider(value: scale, in: FrameSettings.letterheadScaleRange, step: 0.05)
                        .environment(\.layoutDirection, .leftToRight)
                    Text("\(ArabicFormat.number(Int((scale.wrappedValue * 100).rounded()), vm.report.page.numerals))٪")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }

                HStack(spacing: 8) {
                    Text("الموضع").font(.caption).foregroundStyle(.secondary)
                    nudge("chevron.up") { offset.wrappedValue = max(offset.wrappedValue - 2, offsetRange.lowerBound) }
                    Slider(value: offset, in: offsetRange, step: 1)
                    nudge("chevron.down") { offset.wrappedValue = min(offset.wrappedValue + 2, offsetRange.upperBound) }
                    if offset.wrappedValue != 0 {
                        Button {
                            offset.wrappedValue = 0
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("الموضع الأصلي")
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }

            HStack {
                PhotosPicker(selection: selection, matching: .images) {
                    Label(data == nil ? "رفع من الصور" : "تغيير", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
                if data != nil {
                    Button(role: .destructive) {
                        vm.removeLetterhead(top: top)
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

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 26, height: 26)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }

    private func loadLetterhead(_ item: PhotosPickerItem?, top: Bool) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await vm.importLetterhead(data, top: top)
            } else {
                vm.errorMessage = "تعذر تحميل الصورة المختارة."
            }
        }
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
