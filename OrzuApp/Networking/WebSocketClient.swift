import Foundation
import Combine

enum ServerEvent {
    case newMessage(Message)
    case error(message: String)
    /// Сообщение отредактировали или поменялись реакции.
    case messageUpdated(Message)
    /// Удалено у всех — или у этого пользователя на другом его устройстве.
    case messageDeleted(chatId: String, messageId: String)
    /// Собеседник userId получил (или прочитал) сообщения чата, отправленные не позже `at`.
    case receipt(chatId: String, userId: String, kind: ReceiptKind, at: Date)
    /// Участник чата набирает сообщение. Сервер шлёт это не чаще раза в две секунды на человека.
    case typing(chatId: String, userId: String)
    /// Собеседник по личному чату вошёл в сеть или вышел из неё.
    case presence(userId: String, presence: Presence)
    /// Чат закрепили или открепили — событие приходит только самому пользователю, на все его устройства.
    case chatPinned(chatId: String, pinnedAt: Date?)
    /// Звук чата отключили (до mutedUntil) или включили (nil) — только самому пользователю, на все его устройства.
    case chatMuted(chatId: String, mutedUntil: Date?)
    /// Сменилось закреплённое сообщение чата (messageId = nil — открепили).
    case chatPinnedMessage(chatId: String, messageId: String?)
    /// Историю чата очистили: у себя (событие только этому пользователю) или у всех.
    case chatCleared(chatId: String)
    /// Чат удалён у обоих собеседников.
    case chatDeleted(chatId: String)
    case callIncoming(IncomingCall)
    /// userId вошёл в звонок — каждый, кто уже в звонке, шлёт ему offer (mesh).
    case callAccepted(callId: String, userId: String, name: String)
    /// Список уже вошедших — приходит тому, кто только что принял звонок.
    case callMembers(callId: String, members: [(userId: String, name: String)])
    case callLeft(callId: String, userId: String)
    case callOffer(callId: String, from: String, sdp: String)
    case callAnswer(callId: String, from: String, sdp: String)
    case callIce(callId: String, from: String, candidate: String, sdpMLineIndex: Int32, sdpMid: String?)
    case callEnd(callId: String, reason: String)
    case callUnavailable(callId: String)
    case callBusy(callId: String)
    /// Возникла пара: лайк оказался взаимным или ответили на первое сообщение.
    case datingMatch(DatingMatch)
    /// Пришло первое сообщение от того, с кем пары ещё нет.
    case datingIntro(IncomingIntro)
    /// Пару разорвали — её чат удалён у обоих.
    case datingUnmatched(matchId: String, chatId: String?)
    /// «Путь к браку» пары изменился: ступень, предложение или чек-лист.
    case datingJourney(matchId: String)
    /// Приглашение на встречу создано или на него ответили.
    case datingMeeting(DatingMeeting)
    /// Модератор проверил селфи, фото или видео анкеты — статусы в анкете изменились.
    case datingModerated
    /// Новый запрос на переписку или на мой запрос ответили: ящик «Запросы» и список чатов перечитываются.
    case chatRequestsChanged
    /// Тревога того, кто добавил вас в доверенные контакты (или обновление её геопозиции).
    case sosAlert(SosAlert)
    case sosClosed(SosAlert)
    /// Санкция модератора: предупреждение, скрытие анкеты или блокировка аккаунта.
    case accountSanction(type: String, reason: String)
    /// Тот, кто добавил вас в доверенные контакты, идёт на встречу и поделился, с кем, где и когда.
    case meetingShared(SharedMeeting)
}

enum ReceiptKind {
    case delivered, read
}

/// Встреча, которой с вами поделились как с доверенным контактом (см. POST /dating/meetings/:id/share).
struct SharedMeeting: Decodable, Identifiable, Hashable {
    let userId: String
    let displayName: String
    let withUserId: String
    let withDisplayName: String
    let startsAt: Date
    let place: String

    /// Сервер не даёт встрече отдельного идентификатора в этом событии — хватает пары «кто и когда».
    var id: String { "\(userId):\(startsAt.timeIntervalSince1970)" }
}

struct IncomingCall: Equatable {
    let callId: String
    let chatId: String
    let fromName: String
    let isVideo: Bool
    let isGroup: Bool
    let title: String?

    /// Разбирает и WS-событие call.incoming, и поле "call" из VoIP-push — сервер кладёт туда одно и то же.
    init?(json: [String: Any]) {
        guard
            let callId = json["callId"] as? String,
            let chatId = json["chatId"] as? String,
            let fromName = json["fromName"] as? String
        else { return nil }
        self.callId = callId
        self.chatId = chatId
        self.fromName = fromName
        self.isVideo = json["video"] as? Bool ?? false
        self.isGroup = json["isGroup"] as? Bool ?? false
        self.title = json["title"] as? String
    }

    /// Заголовок экрана звонка: в группе — её название, в личном — имя звонящего.
    var displayTitle: String {
        guard isGroup else { return fromName }
        return "\(title ?? "Группа") · \(fromName)"
    }
}

/// Единственное WS-соединение на всё приложение: сервер рассылает новые сообщения по всем чатам пользователя,
/// а конкретные экраны сами фильтруют события по chatId через `events`.
@MainActor
final class WebSocketClient: NSObject, ObservableObject {
    static let shared = WebSocketClient()

    let events = PassthroughSubject<ServerEvent, Never>()

    /// Код, которым RealtimeGateway закрывает сокет при протухшем или невалидном access-токене.
    private static let unauthorizedCloseCode = 4001
    private static let maxQueuedSignals = 100

    /// Сервер прислал "ready": сокет авторизован. До этого сигналы звонка копятся в очереди — после VoIP-push
    /// приложение отправляет call.check/call.accept раньше, чем соединение успело установиться.
    /// По нему же плашка над вкладками показывает «Соединение…».
    @Published private(set) var isReady = false
    private var queuedSignals: [[String: Any]] = []

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    private lazy var decoder = ISO8601Coding.makeDecoder()

    private override init() {}

    func connect() {
        guard task == nil, let accessToken = TokenStore.shared.accessToken else { return }

        var components = URLComponents(url: AppConfig.wsBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]

        let webSocketTask = session.webSocketTask(with: components.url!)
        task = webSocketTask
        webSocketTask.resume()
        listen()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isReady = false
        queuedSignals.removeAll()
    }

    /// «Печатает…» собеседникам. Без соединения молча пропускаем: статус набора не стоит ни очереди, ни реконнекта.
    func sendTyping(chatId: String) {
        guard isReady else { return }
        sendJSON(["type": "typing", "chatId": chatId])
    }

    func sendCall(_ payload: [String: Any]) {
        guard isReady else {
            if queuedSignals.count < Self.maxQueuedSignals { queuedSignals.append(payload) }
            connect()
            return
        }
        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        task.send(.data(data)) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.reconnect() }
            }
        }
    }

    private func listen() {
        guard let listeningTask = task else { return }

        listeningTask.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                // После disconnect()/reconnect() старая задача может ещё отдать событие или ошибку отмены —
                // без этой проверки они запустили бы лишний реконнект или второй цикл чтения на новом соединении.
                guard self.task === listeningTask else { return }

                switch result {
                case .success(let message):
                    self.handle(message: message)
                    self.listen()
                case .failure:
                    self.reconnect(closeCode: listeningTask.closeCode)
                }
            }
        }
    }

    private func reconnect(closeCode: URLSessionWebSocketTask.CloseCode = .invalid) {
        task = nil
        isReady = false
        Task { @MainActor in
            // Без обновления токена переподключение с протухшим access-токеном зациклилось бы: сервер снова закрыл бы сокет с 4001.
            if closeCode.rawValue == Self.unauthorizedCloseCode {
                let isSessionAlive = await refreshTokens()
                guard isSessionAlive else { return }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.connect()
        }
    }

    /// false — refresh-токен недействителен (токены уже очищены), переподключаться нечем.
    /// Сетевой сбой считаем временным: сессия жива, следующая попытка реконнекта повторит refresh.
    private func refreshTokens() async -> Bool {
        do {
            try await APIClient.shared.refreshTokensIfNeeded()
            return true
        } catch APIError.unauthorized {
            return false
        } catch {
            return true
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let raw): data = raw
        case .string(let text): data = Data(text.utf8)
        @unknown default: return
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        switch type {
        case "ready":
            isReady = true
            let signals = queuedSignals
            queuedSignals.removeAll()
            for signal in signals {
                sendJSON(signal)
            }

        case "message.new":
            guard
                let messageData = try? JSONSerialization.data(withJSONObject: json["message"] as Any),
                let message = try? decoder.decode(Message.self, from: messageData)
            else { return }
            events.send(.newMessage(message))

        case "message.updated":
            guard
                let messageData = try? JSONSerialization.data(withJSONObject: json["message"] as Any),
                let message = try? decoder.decode(Message.self, from: messageData)
            else { return }
            events.send(.messageUpdated(message))

        case "message.deleted":
            guard let chatId = json["chatId"] as? String, let messageId = json["messageId"] as? String else { return }
            events.send(.messageDeleted(chatId: chatId, messageId: messageId))

        case "chat.delivered", "chat.read":
            guard
                let chatId = json["chatId"] as? String,
                let userId = json["userId"] as? String,
                let atString = json["at"] as? String,
                let at = ISO8601Coding.date(from: atString)
            else { return }
            events.send(.receipt(chatId: chatId, userId: userId, kind: type == "chat.read" ? .read : .delivered, at: at))

        case "typing":
            guard let chatId = json["chatId"] as? String, let userId = json["userId"] as? String else { return }
            events.send(.typing(chatId: chatId, userId: userId))

        case "presence":
            guard let userId = json["userId"] as? String, let presence: Presence = decode(json["presence"]) else { return }
            events.send(.presence(userId: userId, presence: presence))

        case "chat.pinned":
            guard let chatId = json["chatId"] as? String else { return }
            // pinnedAt = null означает «откреплён», а не «поле не пришло».
            events.send(.chatPinned(chatId: chatId, pinnedAt: (json["pinnedAt"] as? String).flatMap(ISO8601Coding.date(from:))))

        case "chat.muted":
            guard let chatId = json["chatId"] as? String else { return }
            events.send(.chatMuted(chatId: chatId, mutedUntil: (json["mutedUntil"] as? String).flatMap(ISO8601Coding.date(from:))))

        case "chat.pinnedMessage":
            guard let chatId = json["chatId"] as? String else { return }
            events.send(.chatPinnedMessage(chatId: chatId, messageId: json["messageId"] as? String))

        case "chat.cleared":
            guard let chatId = json["chatId"] as? String else { return }
            events.send(.chatCleared(chatId: chatId))

        case "chat.deleted":
            guard let chatId = json["chatId"] as? String else { return }
            events.send(.chatDeleted(chatId: chatId))

        case "safety.meetingShared":
            guard let meeting: SharedMeeting = decode(json["meeting"]) else { return }
            events.send(.meetingShared(meeting))

        case "dating.match":
            guard let match: DatingMatch = decode(json["match"]) else { return }
            events.send(.datingMatch(match))

        case "dating.intro":
            guard let intro: IncomingIntro = decode(json["intro"]) else { return }
            events.send(.datingIntro(intro))

        case "dating.unmatched":
            guard let matchId = json["matchId"] as? String else { return }
            events.send(.datingUnmatched(matchId: matchId, chatId: json["chatId"] as? String))

        case "dating.journey":
            guard let matchId = json["matchId"] as? String else { return }
            events.send(.datingJourney(matchId: matchId))

        case "dating.meeting":
            guard let meeting: DatingMeeting = decode(json["meeting"]) else { return }
            events.send(.datingMeeting(meeting))

        case "chat.request", "chat.requestAccepted":
            events.send(.chatRequestsChanged)

        case "dating.verification", "dating.photoModerated", "dating.videoModerated":
            // Что именно проверили, клиенту не важно: он перечитывает анкету целиком.
            events.send(.datingModerated)

        case "safety.sos", "safety.sos.location":
            guard let alert: SosAlert = decode(json["alert"]) else { return }
            events.send(.sosAlert(alert))

        case "safety.sos.closed":
            guard let alert: SosAlert = decode(json["alert"]) else { return }
            events.send(.sosClosed(alert))

        case "account.sanction":
            guard
                let sanction = json["sanction"] as? [String: Any],
                let type = sanction["type"] as? String
            else { return }
            events.send(.accountSanction(type: type, reason: sanction["reason"] as? String ?? ""))

        case "error":
            let text = json["message"] as? String ?? "Неизвестная ошибка"
            events.send(.error(message: text))

        case "call.incoming":
            guard let call = IncomingCall(json: json) else { return }
            events.send(.callIncoming(call))

        case "call.accepted":
            guard let callId = json["callId"] as? String, let userId = json["userId"] as? String else { return }
            events.send(.callAccepted(callId: callId, userId: userId, name: json["name"] as? String ?? ""))

        case "call.members":
            guard let callId = json["callId"] as? String, let members = json["members"] as? [[String: Any]] else { return }
            let parsed = members.compactMap { member -> (userId: String, name: String)? in
                guard let userId = member["userId"] as? String else { return nil }
                return (userId, member["name"] as? String ?? "")
            }
            events.send(.callMembers(callId: callId, members: parsed))

        case "call.left":
            guard let callId = json["callId"] as? String, let userId = json["userId"] as? String else { return }
            events.send(.callLeft(callId: callId, userId: userId))

        case "call.offer":
            guard let callId = json["callId"] as? String, let from = json["from"] as? String, let sdp = json["sdp"] as? String else { return }
            events.send(.callOffer(callId: callId, from: from, sdp: sdp))

        case "call.answer":
            guard let callId = json["callId"] as? String, let from = json["from"] as? String, let sdp = json["sdp"] as? String else { return }
            events.send(.callAnswer(callId: callId, from: from, sdp: sdp))

        case "call.ice":
            guard
                let callId = json["callId"] as? String,
                let from = json["from"] as? String,
                let candidateJSON = json["candidate"] as? [String: Any],
                let candidate = candidateJSON["candidate"] as? String,
                let sdpMLineIndex = candidateJSON["sdpMLineIndex"] as? Int
            else { return }
            events.send(.callIce(callId: callId, from: from, candidate: candidate, sdpMLineIndex: Int32(sdpMLineIndex), sdpMid: candidateJSON["sdpMid"] as? String))

        case "call.end":
            guard let callId = json["callId"] as? String else { return }
            events.send(.callEnd(callId: callId, reason: json["reason"] as? String ?? "hangup"))

        case "call.unavailable":
            guard let callId = json["callId"] as? String else { return }
            events.send(.callUnavailable(callId: callId))

        case "call.busy":
            guard let callId = json["callId"] as? String else { return }
            events.send(.callBusy(callId: callId))

        default:
            break
        }
    }

    /// Вложенный объект события (пара, первое сообщение, встреча) — из JSON в модель.
    private func decode<T: Decodable>(_ value: Any?) -> T? {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
