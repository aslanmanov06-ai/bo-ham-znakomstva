import AVFoundation
import SwiftUI
import UIKit

/// Своя камера вместо UIImagePickerController: системная показывает фронтальную камеру зеркально, а снимок
/// сохраняет неотражённым — после съёмки фото «переворачивалось». Здесь и превью, и снимок как в зеркале.
/// Только фронтальная камера и без галереи: селфи для проверки анкеты — только снятое сейчас,
/// иначе проверку прошли бы чужим фото из интернета.
struct SelfieCamera: View {
    /// Жест подсказкой поверх камеры — чтобы не держать его в голове во время съёмки.
    let gesture: SelfieGesture?
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = SelfieCaptureSession()
    /// Снятое фото: как у системной камеры — «Переснять» или «Использовать фото».
    @State private var photo: UIImage?
    @State private var failed = false

    /// На Симуляторе и iPad без фронтальной камеры снять селфи нечем.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    /// Спрашивает доступ, если человек ещё не отвечал. Отказ бросает MediaPermissionError.camera с подсказкой про Настройки.
    static func ensureAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw MediaPermissionError.camera }
        default:
            throw MediaPermissionError.camera
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                if failed {
                    Text("Камера недоступна — закройте и попробуйте ещё раз")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            VStack(spacing: 12) {
                Spacer()
                // Подсказка внизу, над затвором: у верхнего края её закрывали «чёлка» и Dynamic Island.
                if photo == nil, let gesture {
                    GestureHint(gesture: gesture)
                }
                bottomBar
            }
        }
        .task {
            do {
                try await camera.start()
            } catch {
                failed = true
            }
        }
        .onDisappear { camera.stop() }
    }

    /// Нижняя панель как у системной камеры: «Отменить» и затвор, после снимка — «Переснять» и «Использовать фото».
    private var bottomBar: some View {
        ZStack {
            if photo == nil {
                Button(action: shoot) {
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                        .padding(5)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(failed || camera.isCapturing)
                .accessibilityLabel("Сделать снимок")
            }
            HStack {
                if photo == nil {
                    Button("Отменить") { dismiss() }
                } else {
                    Button("Переснять") { photo = nil }
                    Spacer()
                    Button("Использовать фото") {
                        if let photo { onCapture(photo) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                Spacer()
            }
            .font(.app(.body))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.45).ignoresSafeArea(edges: .bottom))
    }

    private func shoot() {
        Task {
            if let image = await camera.capture() {
                photo = image
            }
        }
    }
}

/// Сессия фронтальной камеры для одного снимка.
/// @unchecked Sendable: сессия настраивается и запускается только на sessionQueue, а isCapturing и
/// продолжение снимка меняются только на главном потоке.
final class SelfieCaptureSession: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published private(set) var isCapturing = false

    private let output = AVCapturePhotoOutput()
    // startRunning блокирует поток — вся работа с сессией на своей очереди.
    private let sessionQueue = DispatchQueue(label: "SelfieCaptureSession.session")
    private var continuation: CheckedContinuation<UIImage?, Never>?
    /// Портретная ориентация: у фронтальной камеры буфер «лежит на боку».
    private static let portraitRotationAngle: CGFloat = 90

    func start() async throws {
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

    func stop() {
        sessionQueue.async { self.session.stopRunning() }
    }

    /// Снимок как в зеркале — таким, каким человек видел себя в превью. nil — снять не удалось.
    @MainActor
    func capture() async -> UIImage? {
        guard !isCapturing, session.isRunning else { return nil }
        if let connection = output.connection(with: .video) {
            // Без отключения автоподстройки установка isVideoMirrored бросает исключение.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            if connection.isVideoRotationAngleSupported(Self.portraitRotationAngle) {
                connection.videoRotationAngle = Self.portraitRotationAngle
            }
        }
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }

    private func configure() throws {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CocoaError(.featureUnsupported)
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
        session.addInput(input)
        session.addOutput(output)
    }
}

extension SelfieCaptureSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        Task { @MainActor in
            self.continuation?.resume(returning: image)
            self.continuation = nil
        }
    }
}

/// Плашка «✌️ Покажите: два пальца — знак V» над затвором камеры (макет «Камера с подсказкой жеста»).
private struct GestureHint: View {
    let gesture: SelfieGesture

    var body: some View {
        HStack(spacing: 10) {
            Text(gesture.emoji)
                .font(.system(size: 24))
            Text("Покажите: \(gesture.title.lowercased(with: Locale(identifier: "ru_RU")))")
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 18 / 255, green: 14 / 255, blue: 18 / 255).opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}
