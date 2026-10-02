import SwiftUI
import WebRTC

/// Мост track → view: RTCVideoTrack сам не View, поэтому подписываем/отписываем рендерер вручную.
struct RTCVideoRenderView: UIViewRepresentable {
    let track: RTCVideoTrack?
    /// Своя фронтальная камера — как в зеркале (так привычно и так делает FaceTime). Собеседнику кадр уходит
    /// неотражённым: WebRTC зеркалит только здесь, при показе.
    var mirrored = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if let previous = context.coordinator.currentTrack, previous !== track {
            previous.remove(uiView)
        }
        if let track, context.coordinator.currentTrack !== track {
            track.add(uiView)
        }
        context.coordinator.currentTrack = track
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.currentTrack?.remove(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}
