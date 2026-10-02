import AVFoundation
import Combine
import Foundation
// Заголовки WebRTC не размечены под Sendable — без @preconcurrency каждый колбэк даёт предупреждение.
@preconcurrency import WebRTC
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
    /// Своё превью зеркалим только для фронтальной камеры: основную показываем как есть.
    @Published private(set) var isFrontCamera = true
    /// iPhone счёл видео собеседника откровенным (RouletteSensitiveGuard) — показываем заглушку с выбором.
    @Published private(set) var isSensitiveHidden = false
    /// Соединение не установилось или оборвалось — разговор продолжать бессмысленно.
    let connectionFailed = PassthroughSubject<String, Never>()

    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Roulette")
    private var iceServers: [RTCIceServer] = []
    private var audioTrack: RTCAudioTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var cameraPosition = AVCaptureDevice.Position.front {
        didSet { isFrontCamera = cameraPosition == .front }
    }
    private var connection: RTCPeerConnection?
    private var sessionId: String?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false
    /// Этот телефон шлёт offer — он же перезапускает ICE, когда связь прервалась.
    private var isInitiator = false
    private var isRestartingIce = false
    private var watchdog: Task<Void, Never>?
    /// RouletteSensitiveGuard (iOS 26+) текущего собеседника.
    private var sensitiveGuard: AnyObject?
    /// Сколько ждём первого соединения с собеседником и восстановления после обрыва, прежде чем искать следующего.
    private static let connectTimeout: TimeInterval = 15
    private static let reconnectTimeout: TimeInterval = 10
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
        guard let audioTrack, let localTrack else {
            connectionFailed.send(id)
            return
        }

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
        if let sender = connection.add(localTrack, streamIds: ["roulette"]) {
            VideoQuality.configure(sender, maxBitrateBps: VideoQuality.oneToOneBitrateBps)
        }
        self.connection = connection
        sessionId = id
        isInitiator = initiator
        if initiator { sendOffer() }
        startWatchdog(after: Self.connectTimeout)
    }

    /// Не соединились за отведённое время (собеседник не ответил, TURN недоступен) — ICE сам может так и не дойти
    /// до .failed, а человек смотрел бы на «Соединяемся…» бесконечно.
    private func startWatchdog(after delay: TimeInterval) {
        watchdog?.cancel()
        guard let id = sessionId else { return }
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.sessionId == id else { return }
            self.connectionFailed.send(id)
        }
    }

    private func sendOffer() {
        guard let connection else { return }
        sendLocalDescription(type: "roulette.offer") { constraints, completion in
            connection.offer(for: constraints, completionHandler: completion)
        }
    }

    /// Связь прервалась (сменилась сеть) — новые ICE-кандидаты и offer, не дожидаясь, пока соединение упадёт совсем.
    fileprivate func restartIce() {
        guard let connection, isInitiator, !isRestartingIce else { return }
        isRestartingIce = true
        connection.restartIce()
        sendOffer()
    }

    /// «Всё равно показать» на заглушке откровенного видео.
    func showSensitiveVideo() {
        isSensitiveHidden = false
        setRemoteAudio(enabled: true)
        if #available(iOS 26.0, *) { (sensitiveGuard as? RouletteSensitiveGuard)?.continueStream() }
    }

    private func startSensitiveGuard(for track: RTCVideoTrack?) {
        stopSensitiveGuard()
        guard #available(iOS 26.0, *), let track, let sessionId else { return }
        sensitiveGuard = RouletteSensitiveGuard(participant: sessionId, track: track) { [weak self] hide, muteAudio in
            guard let self, hide, !self.isSensitiveHidden else { return }
            self.isSensitiveHidden = true
            if muteAudio { self.setRemoteAudio(enabled: false) }
        }
    }

    private func stopSensitiveGuard() {
        if #available(iOS 26.0, *) { (sensitiveGuard as? RouletteSensitiveGuard)?.stop() }
        sensitiveGuard = nil
        isSensitiveHidden = false
    }

    private func setRemoteAudio(enabled: Bool) {
        for receiver in connection?.receivers ?? [] {
            if let audio = receiver.track as? RTCAudioTrack { audio.isEnabled = enabled }
        }
    }

    /// Разговор закончился: камера остаётся включённой — следующий собеседник найдётся через секунды.
    func endSession() {
        watchdog?.cancel()
        watchdog = nil
        stopSensitiveGuard()
        connection?.close()
        connection = nil
        sessionId = nil
        pendingCandidates.removeAll()
        hasRemoteDescription = false
        isInitiator = false
        isRestartingIce = false
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
                let candidates = self.pendingCandidates
                self.pendingCandidates.removeAll()
                next?()
                // answer не ждёт отложенных кандидатов — как и раньше, когда их добавляли колбэками.
                for candidate in candidates {
                    do {
                        try await connection.add(candidate)
                    } catch {
                        self.logger.error("add pending candidate: \(error.localizedDescription, privacy: .public)")
                    }
                }
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
                do {
                    try await connection.setLocalDescription(sdp)
                } catch {
                    self.logger.error("setLocalDescription: \(error.localizedDescription, privacy: .public)")
                    return
                }
                WebSocketClient.shared.sendRoulette(["type": type, "sessionId": sessionId, "sdp": sdp.sdp])
            }
        }
    }

    // MARK: - Камера и звук

    private func startCapture(position: AVCaptureDevice.Position) {
        guard
            let capturer,
            let camera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position }),
            let quality = VideoQuality.captureFormat(for: camera)
        else { return }
        capturer.startCapture(with: camera, format: quality.format, fps: quality.fps)
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
            self.startSensitiveGuard(for: track)
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
                self.isRestartingIce = false
                self.watchdog?.cancel()
                self.watchdog = nil
            case .disconnected:
                self.restartIce()
                self.startWatchdog(after: Self.reconnectTimeout)
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
