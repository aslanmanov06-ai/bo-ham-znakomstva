import AVFoundation

/// Камера для «кружков»: фронтальная, 480p (минута — несколько МБ), со звуком, не дольше минуты.
final class VideoNoteCamera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    /// Вызывается на главном потоке: запись готова или nil (слишком короткая, ошибка).
    var onFinish: ((MediaRecording?) -> Void)?

    private let output = AVCaptureMovieFileOutput()
    // startRunning блокирует поток — вся работа с сессией на своей очереди.
    private let sessionQueue = DispatchQueue(label: "VideoNoteCamera.session")
    private var timer: Timer?
    private static let tickInterval: TimeInterval = 0.1
    /// Портретная ориентация: у фронтальной камеры буфер «лежит на боку».
    private static let portraitRotationAngle: CGFloat = 90

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw MediaPermissionError.camera }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw MediaPermissionError.microphone }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure()
                    self.session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func shutdown() {
        if output.isRecording { output.stopRecording() }
        sessionQueue.async { self.session.stopRunning() }
        stopTimer()
    }

    @MainActor
    func startRecording() {
        guard !output.isRecording, session.isRunning else { return }
        if let connection = output.connection(with: .video) {
            // Как в зеркале: так же, как пользователь видел себя в превью.
            // Без отключения автоподстройки установка isVideoMirrored бросает исключение.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            if connection.isVideoRotationAngleSupported(Self.portraitRotationAngle) {
                connection.videoRotationAngle = Self.portraitRotationAngle
            }
        }
        output.startRecording(to: MediaRecording.temporaryURL(prefix: "videonote", fileExtension: "mov"), recordingDelegate: self)
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.output.recordedDuration.seconds
            }
        }
    }

    @MainActor
    func stopRecording() {
        guard output.isRecording else { return }
        output.stopRecording()
    }

    private func configure() throws {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .vga640x480
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let microphone = AVCaptureDevice.default(for: .audio)
        else { throw CocoaError(.featureUnsupported) }

        for input in [try AVCaptureDeviceInput(device: camera), try AVCaptureDeviceInput(device: microphone)] {
            guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
            session.addInput(input)
        }
        guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
        session.addOutput(output)
        // Лимит в самой записи: даже если таймер интерфейса отстанет, файл не выйдет длиннее минуты.
        output.maxRecordedDuration = CMTime(seconds: MediaRecording.maxVideoNoteDuration, preferredTimescale: 600)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension VideoNoteCamera: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Достигнутый лимит длительности приходит как «ошибка», но файл при этом записан целиком.
        let finishedSuccessfully = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)

        Task { @MainActor in
            self.stopTimer()
            self.isRecording = false
            // Длительность — из самого файла: recordedDuration после остановки записи не гарантирована.
            guard finishedSuccessfully, let duration = try? await AVURLAsset(url: outputFileURL).load(.duration) else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.onFinish?(nil)
                return
            }
            self.onFinish?(MediaRecording(fileURL: outputFileURL, kind: .videoNote, mimeType: "video/quicktime", duration: duration.seconds))
        }
    }
}
