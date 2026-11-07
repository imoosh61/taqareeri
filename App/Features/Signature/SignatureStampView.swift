import PencilKit
import PhotosUI
import SwiftUI
import UIKit

/// Step 4: employees (names + signatures) and official stamp on the last page.
struct SignatureStampView: View {
    @ObservedObject var vm: ReportEditorViewModel
    @State private var signingEmployee: EmployeeRef?
    @State private var photoTarget: UUID?
    @State private var showPhotoPicker = false
    @State private var signatureItem: PhotosPickerItem?
    @State private var stampItem: PhotosPickerItem?
    @State private var zoomPage: PageRef?

    var body: some View {
        Form {
            Section {
                Toggle("إظهار الأسماء والتوقيعات في آخر صفحة", isOn: $vm.report.footer.showSignatureBlock)
                if vm.report.footer.showSignatureBlock {
                    Button {
                        zoomPage = PageRef(id: vm.pagination.physicalPage(forBodyPage: vm.pagination.lastBodyPage))
                    } label: {
                        Label("معاينة الصفحة الأخيرة", systemImage: "eye")
                    }
                }
            } footer: {
                Text("موظف واحد: يظهر في المنتصف. أكثر من موظف: اسم في اليمين واسم في اليسار. وتُضاف صفحة تلقائياً إن لم تكفِ المساحة.")
            }

            ForEach(Array(vm.report.footer.employees.enumerated()), id: \.element.id) { index, employee in
                employeeSection(index: index, employee: employee)
            }

            Section {
                Button {
                    vm.addEmployee()
                } label: {
                    Label("إضافة موظف", systemImage: "person.badge.plus")
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
                Text("يوضع الختم بين التوقيعات، وتُزال خلفيته البيضاء تلقائياً.")
            }
        }
        .sheet(item: $signingEmployee) { ref in
            SignaturePadView { data in vm.setSignature(png: data, for: ref.id) }
        }
        .sheet(item: $zoomPage) { ref in
            PageZoomSheet(vm: vm, initialPage: ref.id)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $signatureItem, matching: .images)
        .onChange(of: signatureItem) { _, item in
            guard let item, let target = photoTarget else { return }
            load(item) { data in await vm.importSignature(data, for: target) }
            signatureItem = nil
        }
        .onChange(of: stampItem) { _, item in
            guard let item else { return }
            load(item) { data in await vm.importStamp(data) }
            stampItem = nil
        }
    }

    private func employeeSection(index: Int, employee: Employee) -> some View {
        Section {
            TextField("السطر العلوي (مثال: اسم الموظف أو المسمى الوظيفي)", text: labelBinding(employee.id))
            TextField("الاسم", text: nameBinding(employee.id))

            if employee.signaturePNG != nil {
                TransparentImagePreview(data: employee.signaturePNG, placeholder: "")
                    .frame(height: 90)
            }
            HStack {
                Button {
                    signingEmployee = EmployeeRef(id: employee.id)
                } label: {
                    Label("رسم توقيع", systemImage: "signature")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    photoTarget = employee.id
                    showPhotoPicker = true
                } label: {
                    Label("من الصور", systemImage: "photo")
                }
                .buttonStyle(.borderless)
            }
            if employee.signaturePNG != nil {
                Button("حذف التوقيع", role: .destructive) {
                    vm.removeSignature(for: employee.id)
                }
            }
            Button(role: .destructive) {
                vm.removeEmployee(employee.id)
            } label: {
                Label("حذف الموظف", systemImage: "person.badge.minus")
            }
        } header: {
            Text(position(for: index))
        }
    }

    private func position(for index: Int) -> String {
        let count = vm.report.footer.employees.count
        let number = ArabicFormat.number(index + 1, vm.report.page.numerals)
        if count == 1 { return "الموظف \(number) — في المنتصف" }
        if index == count - 1 && index.isMultiple(of: 2) { return "الموظف \(number) — في المنتصف (سطر جديد)" }
        return "الموظف \(number) — " + (index.isMultiple(of: 2) ? "يمين" : "يسار")
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { vm.report.footer.employees.first { $0.id == id }?.label ?? "" },
            set: { value in
                if let index = vm.report.footer.employees.firstIndex(where: { $0.id == id }) {
                    vm.report.footer.employees[index].label = value
                }
            }
        )
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { vm.report.footer.employees.first { $0.id == id }?.name ?? "" },
            set: { value in
                if let index = vm.report.footer.employees.firstIndex(where: { $0.id == id }) {
                    vm.report.footer.employees[index].name = value
                }
            }
        )
    }

    private func load(_ item: PhotosPickerItem, then handle: @escaping (Data) async -> Void) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await handle(data)
            } else {
                vm.errorMessage = "تعذر تحميل الصورة المختارة."
            }
        }
    }
}

struct EmployeeRef: Identifiable {
    let id: UUID
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
