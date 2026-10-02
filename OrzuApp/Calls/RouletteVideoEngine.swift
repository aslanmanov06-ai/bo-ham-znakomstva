import AVFoundation
import Combine
import CoreMedia
import Foundation
import WebRTC
import os

/// Видео рулетки: камера и микрофон живут, пока человек в видеорулетке, а соединение с собеседником пересоздаётся
/// на каждый разговор. В отличие от звонков (CallManager), здесь нет CallKit: аудиосессию включаем сами.
/// Соединение — только через TURN (iceTransportPolicy = relay): прямой кандидат раскрыл бы незнакомцу IP-адрес.
enum RouletteMediaError: LocalizedError {
    case cameraDenied, microphoneDenied

    var errorDescription: String? {
        switch self {
        case .cameraDenied: String(localized: "Нет доступа к камере — разрешите его в настройках iPhone")
        case .microphoneDenied: String(localized: "Нет доступа к микрофону — разрешите его в настройках iPhone")
        }
    }
}

@MainActor
final class RouletteVideoEngine: NSObject, ObservableObject {
    @Published private(set) var localTrack: RTCVideoTrack?
    @Published private(set) var remoteTrack: RTCVideoTrack?
    @Published private(set) var isConnected = false
    @Published private(set) var isMuted = false
    @Published private(set) var isCameraOff = false
    /// Соединение не установилось или оборвалось — разговор продолжать бессмысленно.
    let connectionFailed = PassthroughSubject<String, Never>()

    private static let maxLocalVideoWidth: Int32 = 640

    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Roulette")
    private var iceServers: [RTCIceServer] = []
    private var audioTrack: RTCAudioTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var cameraPosition = AVCaptureDevice.Position.front
    private var connection: RTCPeerConnection?
    private var sessionId: String?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event: event) }
            .store(in: &cancellables)
    }

    var isRunning: Bool { localTrack != nil }

    /// Камера, микрофон и TURN-учётки — один раз на вход в видеорулетку.
    func start() async throws {
        guard !isRunning else { return }
        // requestAccess сразу отвечает, если человек уже решал; первый раз — системный запрос.
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw RouletteMediaError.cameraDenied }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RouletteMediaError.microphoneDenied }
        let servers = try await APIClient.shared.fetchIceServers()
        iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }

        let factory = CallManager.factory
        audioTrack = factory.audioTrack(with: factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)), trackId: "roulette-audio")
        let videoSource = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.capturer = capturer
        localTrack = factory.videoTrack(with: videoSource, trackId: "roulette-video")
        startCapture(position: cameraPosition)
        activateAudio()
    }

    /// Выход из видеорулетки: соединение, камера и звук выключаются.
    func stop() {
        endSession()
        capturer?.stopCapture()
        capturer = nil
        localTrack = nil
        audioTrack = nil
        isMuted = false
        isCameraOff = false
        deactivateAudio()
    }

    /// Новый собеседник. initiator — кто шлёт offer (сервер назначает ровно одного).
    func beginSession(id: String, initiator: Bool) {
        endSession()
        guard let audioTrack, let localTrack else { return }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.iceTransportPolicy = .relay
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = CallManager.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            logger.error("Не удалось создать RTCPeerConnection для рулетки")
            connectionFailed.send(id)
            return
        }
        _ = connection.add(audioTrack, streamIds: ["roulette"])
        _ = connection.add(localTrack, streamIds: ["roulette"])
        self.connection = connection
        sessionId = id
        if initiator {
            sendLocalDescription(type: "roulette.offer") { constraints, completion in
                connection.offer(for: constraints, completionHandler: completion)
            }
        }
    }

    /// Разговор закончился: камера остаётся включённой — следующий собеседник найдётся через секунды.
    func endSession() {
        connection?.close()
        connection = nil
        sessionId = nil
        pendingCandidates.removeAll()
        hasRemoteDescription = false
        remoteTrack = nil
        isConnected = false
    }

    func toggleMute() {
        isMuted.toggle()
        audioTrack?.isEnabled = !isMuted
    }

    func toggleCamera() {
        isCameraOff.toggle()
        localTrack?.isEnabled = !isCameraOff
    }

    func flipCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
        startCapture(position: cameraPosition)
    }

    // MARK: - Сигналинг

    private func handle(event: ServerEvent) {
        guard let connection, let sessionId else { return }
        switch event {
        case .rouletteOffer(let id, let sdp) where id == sessionId:
            setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp), on: connection) { [weak self] in
                self?.sendLocalDescription(type: "roulette.answer") { constraints, completion in
                    connection.answer(for: constraints, completionHandler: completion)
                }
            }
        case .rouletteAnswer(let id, let sdp) where id == sessionId:
            setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp), on: connection, then: nil)
        case .rouletteIce(let id, let candidateSdp, let sdpMLineIndex, let sdpMid) where id == sessionId:
            let candidate = RTCIceCandidate(sdp: candidateSdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            if hasRemoteDescription {
                connection.add(candidate) { [weak self] error in
                    if let error { self?.logger.error("add candidate: \(error.localizedDescription, privacy: .public)") }
                }
            } else {
                pendingCandidates.append(candidate)
            }
        default:
            break
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on connection: RTCPeerConnection, then next: (() -> Void)?) {
        let target = ObjectIdentifier(connection)
        connection.setRemoteDescription(description) { [weak self] error in
            Task { @MainActor in
                // Пока ответ шёл, разговор мог смениться — чужое описание к новому соединению не применяем.
                guard let self, let connection = self.connection, ObjectIdentifier(connection) == target else { return }
                if let error {
                    self.logger.error("setRemoteDescription: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self.hasRemoteDescription = true
                for candidate in self.pendingCandidates {
                    connection.add(candidate) { error in
                        if let error { self.logger.error("add pending candidate: \(error.localizedDescription, privacy: .public)") }
                    }
                }
                self.pendingCandidates.removeAll()
                next?()
            }
        }
    }

    /// offer и answer различаются только методом, который их создаёт; дальше — setLocalDescription и отправка.
    private func sendLocalDescription(
        type: String,
        create: @escaping (RTCMediaConstraints, @escaping @Sendable (RTCSessionDescription?, Error?) -> Void) -> Void
    ) {
        guard let connection, let sessionId else { return }
        create(RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] sdp, error in
            Task { @MainActor in
                guard let self, self.connection === connection, let sdp else {
                    if let error { self?.logger.error("create \(type, privacy: .public): \(error.localizedDescription, privacy: .public)") }
                    return
                }
                connection.setLocalDescription(sdp) { error in
                    Task { @MainActor in
                        if let error {
                            self.logger.error("setLocalDescription: \(error.localizedDescription, privacy: .public)")
                            return
                        }
                        WebSocketClient.shared.sendRoulette(["type": type, "sessionId": sessionId, "sdp": sdp.sdp])
                    }
                }
            }
        }
    }

    // MARK: - Камера и звук

    private func startCapture(position: AVCaptureDevice.Position) {
        guard
            let capturer,
            let camera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position }),
            let format = RTCCameraVideoCapturer.supportedFormats(for: camera)
                .first(where: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= Self.maxLocalVideoWidth }),
            let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate
        else { return }
        capturer.startCapture(with: camera, format: format, fps: Int(fps))
    }

    /// WebRTC настроен на ручной звук (его включает CallKit для звонков) — в рулетке включаем сами.
    private func activateAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoChat, options: [.bluetoothHandsFree, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            logger.error("Аудиосессия рулетки: \(error.localizedDescription, privacy: .public)")
        }
        RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }

    private func deactivateAudio() {
        let session = AVAudioSession.sharedInstance()
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension RouletteVideoEngine: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let track = stream.videoTracks.first
        Task { @MainActor in
            guard self.connection === peerConnection else { return }
            self.remoteTrack = track
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor in
            guard self.connection === peerConnection else { return }
            self.remoteTrack = nil
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            guard self.connection === peerConnection, let sessionId = self.sessionId else { return }
            switch newState {
            case .connected, .completed:
                self.isConnected = true
            case .failed:
                self.connectionFailed.send(sessionId)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            guard self.connection === peerConnection, let sessionId = self.sessionId else { return }
            WebSocketClient.shared.sendRoulette([
                "type": "roulette.ice",
                "sessionId": sessionId,
                "candidate": [
                    "candidate": candidate.sdp,
                    "sdpMLineIndex": candidate.sdpMLineIndex,
                    // JSONSerialization понимает NSNull, а не Optional, обёрнутый в Any.
                    "sdpMid": candidate.sdpMid.map { $0 as Any } ?? NSNull(),
                ],
            ])
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
