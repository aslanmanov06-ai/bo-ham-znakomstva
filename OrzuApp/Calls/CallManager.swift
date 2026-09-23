import AVFoundation
import CallKit
import Combine
import CoreMedia
import Foundation
import PushKit
import WebRTC
import os

enum CallState: Equatable {
    case idle
    case outgoingRinging(title: String, isVideo: Bool)
    case incomingRinging(callId: String, title: String, isVideo: Bool)
    case connecting(title: String, isVideo: Bool)
    case active(title: String, isVideo: Bool, startedAt: Date)
    case ended(reason: String)
}

/// Собеседник в звонке. В личном звонке он один, в групповом — до трёх (mesh, см. backend CallsService).
struct CallParticipant: Identifiable, Equatable {
    let userId: String
    var name: String
    var videoTrack: RTCVideoTrack?
    var isConnected = false

    var id: String { userId }
}

/// Владеет жизненным циклом WebRTC-звонка. Сигналинг идёт через WebSocketClient, сервер видит только SDP/ICE
/// и никогда — медиапотоки. Системный интерфейс звонка (экран блокировки, входящий из фона) — CallKit,
/// а разбудить выгруженное приложение ради входящего может только VoIP-push (PushKit) — см. CallManager+CallKit.
@MainActor
final class CallManager: NSObject, ObservableObject {
    static let shared = CallManager()

    @Published private(set) var state: CallState = .idle
    @Published private(set) var participants: [CallParticipant] = []
    @Published private(set) var isMuted = false
    @Published private(set) var isSpeakerOn = true
    @Published private(set) var isCameraOff = false
    @Published private(set) var localVideoTrack: RTCVideoTrack?

    /// Звонок, о котором знает CallKit: uuid — его идентификатор в системе, id — на нашем сервере.
    struct ActiveCall {
        let id: String
        let uuid: UUID
        let title: String
        let isVideo: Bool
        let isOutgoing: Bool
        var isAnswered: Bool
    }

    /// Соединение с одним собеседником.
    private final class PeerLink {
        let connection: RTCPeerConnection
        var pendingCandidates: [RTCIceCandidate] = []
        var hasRemoteDescription = false

        init(connection: RTCPeerConnection) {
            self.connection = connection
        }
    }

    private static let endedStateDisplayNanoseconds: UInt64 = 800_000_000
    private static let maxLocalVideoWidth: Int32 = 640

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        // Аудиосессию активирует CallKit (provider(_:didActivate:)), а не WebRTC — иначе iOS прервёт звук звонка.
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Call")
    let provider: CXProvider
    let callController = CXCallController()
    let pushRegistry = PKPushRegistry(queue: .main)
    var voipToken: String?
    var isLoggedIn = false

    private(set) var activeCall: ActiveCall?
    private var peers: [String: PeerLink] = [:]
    private var iceServers: [RTCIceServer] = []
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()

        provider.setDelegate(self, queue: nil)
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event: event) }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func startCall(chat: Chat, video: Bool) {
        guard activeCall == nil, chat.canCall else { return }

        let title = chat.type == .group ? chat.displayTitle : (chat.participants.first?.displayName ?? chat.displayTitle)
        let call = ActiveCall(id: UUID().uuidString, uuid: UUID(), title: title, isVideo: video, isOutgoing: true, isAnswered: true)
        activeCall = call
        state = .outgoingRinging(title: title, isVideo: video)

        let action = CXStartCallAction(call: call.uuid, handle: CXHandle(type: .generic, value: chat.id))
        action.isVideo = video
        action.contactIdentifier = title
        callController.request(CXTransaction(action: action)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.logger.error("CallKit отклонил исходящий: \(error.localizedDescription, privacy: .public)")
                self?.finishLocally(reason: "setup-failed")
            }
        }

        Task {
            do {
                try await prepareMedia(video: video)
                WebSocketClient.shared.sendCall(["type": "call.invite", "callId": call.id, "chatId": chat.id, "video": video])
            } catch {
                endCall(reason: "ice-servers-failed")
            }
        }
    }

    /// Кнопки в нашем интерфейсе идут через CallKit, чтобы системный экран звонка и приложение не расходились.
    func acceptIncomingCall() {
        guard let activeCall, !activeCall.isOutgoing, !activeCall.isAnswered else { return }
        request(CXAnswerCallAction(call: activeCall.uuid))
    }

    func declineIncomingCall() {
        endCall(reason: "declined")
    }

    func endCall(reason: String = "hangup") {
        guard let activeCall else { return }
        pendingEndReason = reason
        request(CXEndCallAction(call: activeCall.uuid))
    }

    func toggleMute() {
        guard let activeCall else { return }
        request(CXSetMutedCallAction(call: activeCall.uuid, muted: !isMuted))
    }

    func toggleCamera() {
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {
            logger.error("Не удалось переключить динамик: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Вызывается из CallKit/PushKit (CallManager+CallKit.swift)

    /// Причина, с которой пользователь завершает звонок, — CXEndCallAction её не несёт.
    var pendingEndReason: String?

    /// Входящий из WebSocket или VoIP-push. Повтор того же звонка (оба канала сразу) игнорируется.
    func reportIncoming(_ incoming: IncomingCall, completion: (() -> Void)? = nil) {
        if activeCall?.id == incoming.callId {
            completion?()
            return
        }
        guard activeCall == nil else {
            // Уже разговариваем. Событие из WebSocket просто игнорируем, а VoIP-push (completion != nil) iOS
            // обязывает отразить в CallKit — показываем и сразу гасим.
            if let completion { reportAndImmediatelyEnd(uuid: UUID(), completion: completion) }
            return
        }

        let call = ActiveCall(
            id: incoming.callId,
            uuid: UUID(uuidString: incoming.callId) ?? UUID(),
            title: incoming.displayTitle,
            isVideo: incoming.isVideo,
            isOutgoing: false,
            isAnswered: false
        )
        activeCall = call
        state = .incomingRinging(callId: call.id, title: call.title, isVideo: call.isVideo)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: incoming.chatId)
        update.localizedCallerName = call.title
        update.hasVideo = call.isVideo
        provider.reportNewIncomingCall(with: call.uuid, update: update) { [weak self] error in
            Task { @MainActor in
                if let error {
                    // Например, «Не беспокоить» или блокировка — системы, не наша. Звонящему говорим, что отказались.
                    self?.logger.error("CallKit не показал входящий: \(error.localizedDescription, privacy: .public)")
                    WebSocketClient.shared.sendCall(["type": "call.end", "callId": call.id, "reason": "declined"])
                    self?.finishLocally(reason: "declined")
                }
                completion?()
            }
        }
        // Приложение могло быть разбужено push'ем: подключаемся и спрашиваем, жив ли ещё звонок.
        WebSocketClient.shared.sendCall(["type": "call.check", "callId": call.id])
    }

    func reportAndImmediatelyEnd(uuid: UUID, completion: (() -> Void)?) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "orzu")
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
            Task { @MainActor in
                self?.provider.reportCall(with: uuid, endedAt: nil, reason: .failed)
                completion?()
            }
        }
    }

    func performAnswer() async -> Bool {
        guard var call = activeCall, !call.isAnswered else { return false }
        call.isAnswered = true
        activeCall = call
        state = .connecting(title: call.title, isVideo: call.isVideo)
        do {
            try await prepareMedia(video: call.isVideo)
            WebSocketClient.shared.sendCall(["type": "call.accept", "callId": call.id])
            return true
        } catch {
            WebSocketClient.shared.sendCall(["type": "call.end", "callId": call.id, "reason": "ice-servers-failed"])
            finishLocally(reason: "ice-servers-failed")
            return false
        }
    }

    /// Пользователь завершил звонок (кнопкой или из CallKit) — сообщаем серверу и закрываем всё локально.
    func performEnd() {
        guard let call = activeCall else { return }
        let reason = pendingEndReason ?? (call.isAnswered ? "hangup" : "declined")
        WebSocketClient.shared.sendCall(["type": "call.end", "callId": call.id, "reason": reason])
        finishLocally(reason: reason, reportToCallKit: false)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        localAudioTrack?.isEnabled = !muted
    }

    func audioSessionDidActivate(_ session: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }

    func audioSessionDidDeactivate(_ session: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

    // MARK: - Signaling

    private func handle(event: ServerEvent) {
        switch event {
        case .callIncoming(let incoming):
            reportIncoming(incoming)

        case .callMembers(let callId, let members):
            guard callId == activeCall?.id else { return }
            for member in members {
                upsertParticipant(userId: member.userId, name: member.name)
            }

        case .callAccepted(let callId, let userId, let name):
            guard let call = activeCall, callId == call.id else { return }
            upsertParticipant(userId: userId, name: name)
            if case .outgoingRinging = state {
                state = .connecting(title: call.title, isVideo: call.isVideo)
            }
            // Mesh: offer новому участнику шлёт каждый, кто уже в звонке, — встречных offer не бывает.
            guard let link = peerLink(for: userId) else { return }
            createAndSendLocalDescription(link: link, to: userId, signalType: "call.offer") { constraints, completion in
                link.connection.offer(for: constraints, completionHandler: completion)
            }

        case .callOffer(let callId, let from, let sdp):
            guard callId == activeCall?.id, let link = peerLink(for: from) else { return }
            setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp), on: link) { [weak self] in
                self?.createAndSendLocalDescription(link: link, to: from, signalType: "call.answer") { constraints, completion in
                    link.connection.answer(for: constraints, completionHandler: completion)
                }
            }

        case .callAnswer(let callId, let from, let sdp):
            guard callId == activeCall?.id, let link = peers[from] else { return }
            setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp), on: link, then: nil)

        case .callIce(let callId, let from, let candidateSdp, let sdpMLineIndex, let sdpMid):
            guard callId == activeCall?.id, let link = peerLink(for: from) else { return }
            let candidate = RTCIceCandidate(sdp: candidateSdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            if link.hasRemoteDescription {
                link.connection.add(candidate) { [weak self] error in
                    if let error { self?.logger.error("add candidate: \(error.localizedDescription, privacy: .public)") }
                }
            } else {
                link.pendingCandidates.append(candidate)
            }

        case .callLeft(let callId, let userId):
            guard callId == activeCall?.id else { return }
            removePeer(userId)

        case .callEnd(let callId, let reason):
            guard callId == activeCall?.id else { return }
            finishLocally(reason: reason)

        case .callUnavailable(let callId):
            guard callId == activeCall?.id else { return }
            finishLocally(reason: "unavailable")

        case .callBusy(let callId):
            guard callId == activeCall?.id else { return }
            finishLocally(reason: "busy")

        default:
            break
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on link: PeerLink, then next: (() -> Void)?) {
        link.connection.setRemoteDescription(description) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.error("setRemoteDescription: \(error.localizedDescription, privacy: .public)")
                    return
                }
                link.hasRemoteDescription = true
                for candidate in link.pendingCandidates {
                    link.connection.add(candidate) { error in
                        if let error { self.logger.error("add pending candidate: \(error.localizedDescription, privacy: .public)") }
                    }
                }
                link.pendingCandidates.removeAll()
                next?()
            }
        }
    }

    /// offer/answer различаются только тем, какой метод RTCPeerConnection их создаёт — остальная цепочка
    /// (создать → setLocalDescription → отправить адресату) одинакова, включая переход на MainActor:
    /// колбэки WebRTC приходят с его собственного потока.
    private func createAndSendLocalDescription(
        link: PeerLink,
        to peerId: String,
        signalType: String,
        create: @escaping (RTCMediaConstraints, @escaping (RTCSessionDescription?, Error?) -> Void) -> Void
    ) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        create(constraints) { [weak self] sdp, error in
            Task { @MainActor in
                guard let self, let sdp else {
                    if let error { self?.logger.error("create \(signalType, privacy: .public): \(error.localizedDescription, privacy: .public)") }
                    return
                }
                link.connection.setLocalDescription(sdp) { error in
                    Task { @MainActor in
                        if let error {
                            self.logger.error("setLocalDescription: \(error.localizedDescription, privacy: .public)")
                            return
                        }
                        guard let callId = self.activeCall?.id else { return }
                        WebSocketClient.shared.sendCall(["type": signalType, "callId": callId, "to": peerId, "sdp": sdp.sdp])
                    }
                }
            }
        }
    }

    // MARK: - Media

    private func prepareMedia(video: Bool) async throws {
        let servers = try await APIClient.shared.fetchIceServers()
        iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }

        let audioSource = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        localAudioTrack = Self.factory.audioTrack(with: audioSource, trackId: "audio0")

        if video {
            let videoSource = Self.factory.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: videoSource)
            videoCapturer = capturer
            localVideoTrack = Self.factory.videoTrack(with: videoSource, trackId: "video0")
            startCapturingLocalVideo(capturer: capturer)
        }
        configureAudioSession(video: video)
    }

    /// Только категория и режим: активирует сессию CallKit, иначе системный звонок и наш звук конфликтуют.
    private func configureAudioSession(video: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: video ? .videoChat : .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        } catch {
            logger.error("Аудиосессия: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startCapturingLocalVideo(capturer: RTCCameraVideoCapturer) {
        guard
            let camera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }),
            let format = RTCCameraVideoCapturer.supportedFormats(for: camera)
                .first(where: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= Self.maxLocalVideoWidth }),
            let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate
        else { return }

        capturer.startCapture(with: camera, format: format, fps: Int(fps))
    }

    /// Соединение с собеседником создаётся по первому сигналу от него или о нём; локальные треки общие для всех.
    private func peerLink(for userId: String) -> PeerLink? {
        if let existing = peers[userId] { return existing }
        guard activeCall != nil, let localAudioTrack else { return nil }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            logger.error("Не удалось создать RTCPeerConnection")
            return nil
        }
        _ = connection.add(localAudioTrack, streamIds: ["stream0"])
        if let localVideoTrack {
            _ = connection.add(localVideoTrack, streamIds: ["stream0"])
        }

        let link = PeerLink(connection: connection)
        peers[userId] = link
        upsertParticipant(userId: userId, name: nil)
        return link
    }

    private func upsertParticipant(userId: String, name: String?) {
        if let index = participants.firstIndex(where: { $0.userId == userId }) {
            if let name, !name.isEmpty { participants[index].name = name }
        } else {
            participants.append(CallParticipant(userId: userId, name: name ?? ""))
        }
    }

    private func removePeer(_ userId: String) {
        peers.removeValue(forKey: userId)?.connection.close()
        participants.removeAll { $0.userId == userId }
    }

    fileprivate func peerId(of connection: RTCPeerConnection) -> String? {
        peers.first { $0.value.connection === connection }?.key
    }

    fileprivate func peerDidConnect(_ userId: String) {
        guard let call = activeCall, let index = participants.firstIndex(where: { $0.userId == userId }) else { return }
        participants[index].isConnected = true
        switch state {
        case .active: break
        default:
            state = .active(title: call.title, isVideo: call.isVideo, startedAt: Date())
            if call.isOutgoing {
                provider.reportOutgoingCall(with: call.uuid, connectedAt: nil)
            }
        }
    }

    fileprivate func peerDidFail(_ userId: String) {
        // В личном звонке собеседник единственный — без него звонок бессмыслен; в группе остальные продолжают.
        if participants.count <= 1 {
            endCall(reason: "connection-lost")
        } else {
            removePeer(userId)
        }
    }

    fileprivate func setRemoteVideoTrack(_ track: RTCVideoTrack?, for userId: String) {
        guard let index = participants.firstIndex(where: { $0.userId == userId }) else { return }
        participants[index].videoTrack = track
    }

    // MARK: - Teardown

    /// Закрывает звонок у себя. reportToCallKit=false — когда завершение и так пришло из CallKit (CXEndCallAction).
    func finishLocally(reason: String, reportToCallKit: Bool = true) {
        guard let call = activeCall else { return }
        if reportToCallKit {
            provider.reportCall(with: call.uuid, endedAt: nil, reason: Self.callKitReason(for: reason))
        }

        videoCapturer?.stopCapture()
        videoCapturer = nil
        for link in peers.values { link.connection.close() }
        peers.removeAll()
        participants.removeAll()
        localAudioTrack = nil
        localVideoTrack = nil
        activeCall = nil
        pendingEndReason = nil
        isMuted = false
        isCameraOff = false

        state = .ended(reason: reason)
        Task {
            try? await Task.sleep(nanoseconds: Self.endedStateDisplayNanoseconds)
            if case .ended = state { state = .idle }
        }
    }

    private func request(_ action: CXAction) {
        callController.request(CXTransaction(action: action)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.logger.error("CallKit: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func callKitReason(for reason: String) -> CXCallEndedReason {
        switch reason {
        case "timeout", "unavailable", "busy": return .unanswered
        case "connection-lost", "setup-failed", "ice-servers-failed", "full": return .failed
        default: return .remoteEnded
        }
    }
}

extension CallManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let track = stream.videoTracks.first
        Task { @MainActor in
            guard let userId = self.peerId(of: peerConnection) else { return }
            self.setRemoteVideoTrack(track, for: userId)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor in
            guard let userId = self.peerId(of: peerConnection) else { return }
            self.setRemoteVideoTrack(nil, for: userId)
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            guard let userId = self.peerId(of: peerConnection) else { return }
            switch newState {
            case .connected, .completed:
                self.peerDidConnect(userId)
            case .failed:
                self.peerDidFail(userId)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            guard let callId = self.activeCall?.id, let peerId = self.peerId(of: peerConnection) else { return }
            WebSocketClient.shared.sendCall([
                "type": "call.ice",
                "callId": callId,
                "to": peerId,
                "candidate": [
                    "candidate": candidate.sdp,
                    "sdpMLineIndex": candidate.sdpMLineIndex,
                    // JSONSerialization понимает NSNull, а не "Any, обёрнутый вокруг nil" — иначе сериализация тихо падает.
                    "sdpMid": candidate.sdpMid ?? NSNull(),
                ],
            ])
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
