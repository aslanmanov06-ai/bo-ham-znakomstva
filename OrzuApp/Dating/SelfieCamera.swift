import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Системная камера, сразу фронтальная и без выбора из галереи: селфи для проверки анкеты — только снятое сейчас,
/// иначе проверку прошли бы чужим фото из интернета.
struct SelfieCamera: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// На Симуляторе и iPad без фронтальной камеры снять селфи нечем.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) && UIImagePickerController.isCameraDeviceAvailable(.front)
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

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .front
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
