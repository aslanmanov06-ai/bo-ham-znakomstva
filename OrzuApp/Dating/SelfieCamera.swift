import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Системная камера, сразу фронтальная и без выбора из галереи: селфи для проверки анкеты — только снятое сейчас,
/// иначе проверку прошли бы чужим фото из интернета.
struct SelfieCamera: UIViewControllerRepresentable {
    /// Жест подсказкой поверх камеры — чтобы не держать его в голове во время съёмки.
    let gesture: SelfieGesture?
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
        if let gesture {
            let hint = UIHostingController(rootView: GestureHint(gesture: gesture))
            // Контроллер подсказки живёт, пока открыта камера: без владельца его вид не обновлялся бы.
            context.coordinator.hint = hint
            hint.view.backgroundColor = .clear
            // Подсказка только показывает жест: нажатия проходят к кнопкам камеры.
            hint.view.isUserInteractionEnabled = false
            // Во весь экран камеры и вместе с ним при повороте; наследоваться от UIImagePickerController Apple не велит.
            hint.view.frame = picker.view.bounds
            hint.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            picker.cameraOverlayView = hint.view
        }
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void
        fileprivate var hint: UIViewController?

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

/// Плашка «✌️ Покажите: два пальца — знак V» у верхнего края камеры (макет «Камера с подсказкой жеста»).
private struct GestureHint: View {
    let gesture: SelfieGesture

    var body: some View {
        VStack {
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
            .padding(.top, 8)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
