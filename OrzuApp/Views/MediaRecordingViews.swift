import AVFoundation
import SwiftUI

/// Заменяет строку ввода, пока пишется голосовое: удалить или отправить.
struct VoiceRecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    let onCancel: () -> Void
    let onSend: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onCancel) { GlassIcon(systemImage: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Удалить запись")

                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                    Text(Attachment.formattedDuration(Int(recorder.elapsed)))
                        .font(.app(.body, weight: .semibold).monospacedDigit())
                    LevelWaveform(levels: recorder.levels)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(height: GlassMetrics.controlSize)
                .glassSurface(in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Запись голосового, \(Attachment.formattedDuration(Int(recorder.elapsed)))")

                Button(action: onSend) {
                    BrandCircleIcon(systemImage: "arrow.up")
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Отправить голосовое")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Живая волна громкости: свежие уровни справа, пока запись короче VoiceRecorder.levelCount тиков — слева пусто.
private struct LevelWaveform: View {
    let levels: [CGFloat]
    /// Тишина всё равно видна точкой — иначе кажется, что запись не идёт.
    private static let minBarHeight: CGFloat = 3
    private static let maxBarHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.brand)
                    .frame(width: 3, height: Self.minBarHeight + level * (Self.maxBarHeight - Self.minBarHeight))
            }
        }
        .frame(height: Self.maxBarHeight)
        .animation(.easeOut(duration: 0.1), value: levels)
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
                    errorMessage = String(localized: "Запись слишком короткая или не удалась — попробуйте ещё раз")
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
