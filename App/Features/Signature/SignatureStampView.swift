import PencilKit
import PhotosUI
import SwiftUI
import UIKit

/// Step 4: signer details, drawn/imported signature and official stamp.
struct SignatureStampView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var signatureItem: PhotosPickerItem?
    @State private var stampItem: PhotosPickerItem?
    @State private var showPad = false

    var body: some View {
        Form {
            Section {
                Toggle("إظهار التوقيع والختم أسفل التقرير", isOn: $vm.report.footer.showSignatureBlock)
            } footer: {
                Text("يظهر في آخر صفحة، وتُضاف صفحة جديدة تلقائياً إن لم تكفِ المساحة.")
            }

            Section("بيانات الموقّع") {
                TextField("المسمى الوظيفي (مثال: مدير الإدارة)", text: $vm.report.footer.signerTitle)
                TextField("اسم الموقّع", text: $vm.report.footer.signerName)
            }

            Section("التوقيع") {
                TransparentImagePreview(data: vm.report.footer.signaturePNG, placeholder: "لا يوجد توقيع")
                    .frame(height: 120)
                Button {
                    showPad = true
                } label: {
                    Label("رسم التوقيع بالإصبع", systemImage: "signature")
                }
                PhotosPicker(selection: $signatureItem, matching: .images) {
                    Label("استيراد صورة توقيع", systemImage: "photo")
                }
                if vm.report.footer.signaturePNG != nil {
                    Button(role: .destructive) {
                        vm.report.footer.signaturePNG = nil
                    } label: {
                        Label("حذف التوقيع", systemImage: "trash")
                    }
                }
            }

            Section {
                TransparentImagePreview(data: vm.report.footer.stampPNG, placeholder: "لا يوجد ختم")
                    .frame(height: 120)
                    .overlay {
                        if vm.isProcessingImage { ProgressView() }
                    }
                PhotosPicker(selection: $stampItem, matching: .images) {
                    Label(vm.report.footer.stampPNG == nil ? "إضافة الختم من الصور" : "تغيير الختم", systemImage: "seal")
                }
                if vm.report.footer.stampPNG != nil {
                    Button(role: .destructive) {
                        vm.report.footer.stampPNG = nil
                    } label: {
                        Label("حذف الختم", systemImage: "trash")
                    }
                }
            } header: {
                Text("الختم الرسمي")
            } footer: {
                Text("تُزال الخلفية البيضاء من الختم والتوقيع تلقائياً.")
            }
        }
        .sheet(isPresented: $showPad) {
            SignaturePadView { data in vm.setSignature(png: data) }
        }
        .onChange(of: signatureItem) { _, item in
            load(item) { data in await vm.importSignature(data) }
            signatureItem = nil
        }
        .onChange(of: stampItem) { _, item in
            load(item) { data in await vm.importStamp(data) }
            stampItem = nil
        }
    }

    private func load(_ item: PhotosPickerItem?, then handle: @escaping (Data) async -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await handle(data)
            } else {
                vm.errorMessage = "تعذر تحميل الصورة المختارة."
            }
        }
    }
}

// MARK: - Signature pad

@MainActor
final class SignaturePadModel: ObservableObject {
    let canvas: PKCanvasView

    init() {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        self.canvas = canvas
    }

    func clear() {
        canvas.drawing = PKDrawing()
    }

    /// Transparent PNG of the strokes, rendered in light appearance so ink stays black.
    func exportPNG() -> Data? {
        let drawing = canvas.drawing
        guard !drawing.strokes.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: drawing.bounds.insetBy(dx: -10, dy: -10), scale: 3)
        }
        return image?.pngData()
    }
}

private struct SignatureCanvas: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView { canvas }
    func updateUIView(_ view: PKCanvasView, context: Context) {}
}

struct SignaturePadView: View {
    let onSave: (Data) -> Void
    @StateObject private var model = SignaturePadModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyWarning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                SignatureCanvas(canvas: model.canvas)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.3)))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.35))
                            .frame(height: 1)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 60)
                            .allowsHitTesting(false)
                    }
                Text("وقّع داخل المساحة البيضاء")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    model.clear()
                } label: {
                    Label("مسح", systemImage: "eraser")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("رسم التوقيع")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        if let data = model.exportPNG() {
                            onSave(data)
                            dismiss()
                        } else {
                            showEmptyWarning = true
                        }
                    }
                }
            }
            .alert("لم يتم رسم توقيع بعد", isPresented: $showEmptyWarning) {
                Button("حسناً", role: .cancel) {}
            }
        }
    }
}
