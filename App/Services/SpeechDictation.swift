import AVFoundation
import Foundation
import Speech

/// Live Arabic speech-to-text using the Speech framework.
@MainActor
final class SpeechDictation: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case recording
        case message(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isRecording: Bool { status == .recording }

    func start() async {
        guard status != .recording, status != .preparing else { return }
        status = .preparing

        let speechAuthorized = await Self.requestSpeechAuthorization()
        guard speechAuthorized else {
            status = .message("يجب السماح بالتعرّف على الكلام من الإعدادات > الخصوصية.")
            return
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            status = .message("يجب السماح باستخدام الميكروفون من الإعدادات.")
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            status = .message("خدمة التعرّف على الكلام العربية غير متاحة حالياً. تأكد من الاتصال بالإنترنت.")
            return
        }

        do {
            try beginRecording(with: recognizer)
        } catch {
            stopAudio()
            status = .message("تعذر بدء التسجيل: \(error.localizedDescription)")
        }
    }

    func stop() {
        request?.endAudio()
        stopAudio()
        if status == .recording || status == .preparing {
            status = .idle
        }
    }

    private func beginRecording(with recognizer: SFSpeechRecognizer) throws {
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        Self.installTap(on: engine.inputNode, feeding: request)
        engine.prepare()
        try engine.start()

        transcript = ""
        status = .recording

        task = Self.startRecognition(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                self?.handleRecognition(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    private func handleRecognition(text: String?, isFinal: Bool, failed: Bool) {
        if let text { transcript = text }
        guard isFinal || failed else { return }
        stopAudio()
        if status == .recording {
            status = (failed && transcript.isEmpty)
                ? .message("لم يتم التعرّف على كلام. حاول مرة أخرى.")
                : .idle
        }
    }

    // Authorization, audio and recognition callbacks arrive on background threads, so their
    // closures are created outside the main actor.
    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private func stopAudio() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
