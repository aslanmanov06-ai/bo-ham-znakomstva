import SwiftUI
import WebRTC

/// Мост track → view: RTCVideoTrack сам не View, поэтому подписываем/отписываем рендерер вручную.
struct RTCVideoRenderView: UIViewRepresentable {
    let track: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
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
