import AVFoundation

/// Запись голосового сообщения в AAC (.m4a): моно 32 кбит/с — минута весит ~240 КБ, для речи этого хватает.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Упёрлись в лимит длительности — экран сам отправляет запись.
    @Published private(set) var reachedLimit = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    private static let tickInterval: TimeInterval = 0.2
    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 22_050,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    func start() async throws {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw MediaPermissionError.microphone }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = MediaRecording.temporaryURL(prefix: "voice", fileExtension: "m4a")
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
        isRecording = true
        elapsed = 0
        reachedLimit = false
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// nil — запись короче секунды (случайное нажатие).
    func finish() -> MediaRecording? {
        guard let recorder else { return nil }
        // currentTime обнуляется после stop() — берём длительность до остановки.
        let duration = recorder.currentTime
        recorder.stop()
        reset()
        return MediaRecording(fileURL: recorder.url, kind: .voice, mimeType: "audio/mp4", duration: duration)
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        reset()
    }

    private func tick() {
        guard let recorder else { return }
        elapsed = recorder.currentTime
        if elapsed >= MediaRecording.maxVoiceDuration {
            reachedLimit = true
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        // Отдаём звук другим приложениям (музыка продолжит играть).
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
