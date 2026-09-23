import AVFoundation
import SwiftUI

/// Заменяет строку ввода, пока пишется голосовое: удалить или отправить.
struct VoiceRecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onCancel) { GlassIcon(systemImage: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Удалить запись")

                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text(Attachment.formattedDuration(Int(recorder.elapsed)))
                        .font(.app(.body).monospacedDigit())
                    Spacer(minLength: 0)
                    Text("Запись голосового").font(.app(.footnote)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: GlassMetrics.controlSize)
                .glassSurface(in: Capsule())
                .accessibilityElement(children: .combine)

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
                        .glassSurface(in: Circle(), tint: .accentColor, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отправить голосовое")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Полноэкранная запись «кружка»: нажать — начать, ещё раз — отправить.
struct VideoNoteRecorderView: View {
    let onRecorded: (MediaRecording) -> Void
    @StateObject private var camera = VideoNoteCamera()
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isCancelled = false

    private static let diameter: CGFloat = 280

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            CameraPreview(session: camera.session)
                .frame(width: Self.diameter, height: Self.diameter)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .trim(from: 0, to: camera.elapsed / MediaRecording.maxVideoNoteDuration)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-8)
                }
            Text(Attachment.formattedDuration(Int(camera.elapsed)))
                .font(.app(.title3).monospacedDigit())
                .foregroundStyle(.white)
            if let errorMessage {
                Text(errorMessage)
                    .font(.app(.footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            HStack {
                Button("Отмена", action: cancel)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                recordButton
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            camera.onFinish = { recording in
                if let recording, !isCancelled {
                    onRecorded(recording)
                    dismiss()
                } else if let recording {
                    try? FileManager.default.removeItem(at: recording.fileURL)
                    dismiss()
                } else if isCancelled {
                    dismiss()
                } else {
                    errorMessage = "Запись слишком короткая или не удалась — попробуйте ещё раз"
                }
            }
            do {
                try await camera.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear { camera.shutdown() }
    }

    private var recordButton: some View {
        Button {
            if camera.isRecording {
                camera.stopRecording()
            } else {
                errorMessage = nil
                camera.startRecording()
            }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                RoundedRectangle(cornerRadius: camera.isRecording ? 8 : 30)
                    .fill(.red)
                    .frame(width: camera.isRecording ? 32 : 60, height: camera.isRecording ? 32 : 60)
            }
            .animation(.snappy, value: camera.isRecording)
        }
        .accessibilityLabel(camera.isRecording ? "Остановить и отправить" : "Начать запись")
    }

    /// Во время записи сначала останавливаем её — файл удалится в onFinish.
    private func cancel() {
        isCancelled = true
        if camera.isRecording {
            camera.stopRecording()
        } else {
            dismiss()
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
