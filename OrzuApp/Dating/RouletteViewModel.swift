import Combine
import Foundation

/// Рулетка: выбор режима → поиск → разговор → (собеседник ушёл → следующий) или (взаимно → пара).
/// Сервер ведёт очередь и разговор, пока открыт сокет (backend docs/roulette.md); здесь — только то, что видно на экране.
@MainActor
final class RouletteViewModel: ObservableObject {
    struct Session: Equatable, Identifiable {
        let id: String
        let mode: RouletteMode
        let peer: RoulettePeer
        let startedAt: Date
    }

    enum Phase: Equatable {
        case idle
        case searching(mode: RouletteMode)
        case talking(Session)
        /// Разговор закончился не парой. reported — закончили жалобой. Следующий поиск начнётся в autoSearchAt.
        case ended(Session, reported: Bool, autoSearchAt: Date)
        /// Оба нажали «Нравится». match — nil, пока карточка пары не пришла.
        case matched(Session, match: DatingMatch?)
    }

    /// Через сколько после конца разговора начинается поиск следующего (макет «Собеседник завершил разговор»).
    static let autoSearchDelay: TimeInterval = 3
    /// Видео собеседника первые секунды размыто — на случай неприятного сюрприза.
    static let videoRevealDelay: TimeInterval = 3
    /// Через сколько поиска без результата предлагаем «Расширить» (макет «Долгий поиск»).
    static let expandOfferAfter: TimeInterval = 45
    /// Сколько после конца разговора ещё можно нажать «Нравится» — как на сервере (LIKE_AFTER_END_MS).
    static let likeAfterEndWindow: TimeInterval = 5 * 60
    /// Как часто обновлять «сейчас здесь N» на экранах выбора режима и поиска.
    static let onlineRefreshInterval: TimeInterval = 10
    private static let typingVisibleFor: TimeInterval = 4
    private static let typingSendInterval: TimeInterval = 2

    @Published private(set) var phase = Phase.idle
    @Published private(set) var status: RouletteStatus?
    @Published var selectedMode = RouletteMode.video
    @Published private(set) var messages: [RouletteChatMessage] = []
    @Published private(set) var liked = false
    @Published private(set) var peerTypingUntil: Date?
    @Published private(set) var cityWaitSeconds = 15
    @Published private(set) var searchStartedAt = Date()
    /// Поиск расширен кнопкой «Расширить»: возраст шире, сразу вся страна.
    @Published private(set) var searchExpanded = false
    /// Возраст, по которому сервер ищет сейчас (после расширения — шире, чем в «Кого ищу»).
    @Published private(set) var searchAges: ClosedRange<Int>?
    /// Когда закончился последний разговор — «Нравится» после него работает likeAfterEndWindow.
    private var endedAt = Date.distantPast
    /// Короткое пояснение под полем ввода или кнопками (контакты нельзя, слишком часто…).
    @Published var notice: String?
    @Published var errorMessage: String?
    /// Открыта жалоба на этого собеседника. Пока она открыта, следующий поиск сам не начинается — даже если собеседник ушёл.
    @Published var reportTarget: Session?

    let video = RouletteVideoEngine()

    private var autoSearchTask: Task<Void, Never>?
    private var reminderUpdate: Task<Void, Never>?
    private var lastTypingSentAt = Date.distantPast
    /// Карточки пар из dating.match: сервер присылает её раньше, чем roulette.ended с matchId.
    private var recentMatches: [String: DatingMatch] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event: event) }
            .store(in: &cancellables)
        // Сокет оборвался — сервер уже вывел нас из рулетки; делать вид, что разговор идёт, нельзя.
        WebSocketClient.shared.$isReady
            .removeDuplicates()
            .sink { [weak self] isReady in
                guard let self, !isReady, self.isInRoulette else { return }
                // Пара уже создана на сервере — её экран обрыв связи не отменяет.
                if case .matched = self.phase { return }
                self.finish()
                self.errorMessage = String(localized: "Соединение прервалось — начните рулетку заново")
            }
            .store(in: &cancellables)
        // Начался обычный звонок — камера и звук нужны ему.
        CallManager.shared.$state
            .sink { [weak self] state in
                guard let self, state != .idle, self.isInRoulette else { return }
                self.stop()
            }
            .store(in: &cancellables)
        video.connectionFailed
            .sink { [weak self] sessionId in
                guard let self, case .talking(let session) = self.phase, session.id == sessionId else { return }
                self.notice = String(localized: "Видео не соединилось — ищем следующего")
                self.next()
            }
            .store(in: &cancellables)
    }

    /// Человек в рулетке (ищет, разговаривает или ждёт следующего) — панель вкладок прячется.
    var isInRoulette: Bool { phase != .idle }

    var isPeerTyping: Bool {
        guard let peerTypingUntil else { return false }
        return peerTypingUntil > Date()
    }

    func loadStatus() async {
        do {
            let status = try await APIClient.shared.fetchRouletteStatus()
            // Переключатель напоминания уже сменился у человека на глазах — пока запрос шёл, не откатываем его.
            var fresh = status
            if reminderUpdate != nil { fresh.reminder = self.status?.reminder }
            self.status = fresh
            // Видео по умолчанию, если оно доступно; иначе — переписка.
            if !isInRoulette, !status.modes.video.available, status.modes.text.available { selectedMode = .text }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(_ mode: RouletteMode) async {
        notice = nil
        selectedMode = mode
        cancelAutoSearch()
        if mode == .video {
            do {
                try await video.start()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            video.stop()
        }
        join(mode)
    }

    /// Счётчик «сейчас здесь» — тихо, без сообщения об ошибке: экран и без него работает.
    func refreshOnline() async {
        guard let status = try? await APIClient.shared.fetchRouletteStatus() else { return }
        var fresh = status
        if reminderUpdate != nil { fresh.reminder = self.status?.reminder }
        self.status = fresh
    }

    /// «Напомнить о вечере рулетки». Переключатель меняется сразу; не сохранилось — возвращается обратно.
    func setReminder(_ enabled: Bool) {
        let previous = status?.reminder
        status?.reminder = enabled
        reminderUpdate?.cancel()
        reminderUpdate = Task { [weak self] in
            do {
                try await APIClient.shared.setRouletteReminder(enabled)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.status?.reminder = previous
                self.errorMessage = error.localizedDescription
            }
            self?.reminderUpdate = nil
        }
    }

    /// «Подходящих пока нет → Расширить».
    func expandSearch() {
        guard case .searching = phase, !searchExpanded else { return }
        guard WebSocketClient.shared.sendRoulette(["type": "roulette.expand"]) else {
            notice = String(localized: "Нет подключения к интернету")
            return
        }
        searchExpanded = true
    }

    /// Возраст после «Расширить» — тот же расчёт, что на сервере (EXPAND_AGE_YEARS, не младше 18).
    var expandedAges: ClosedRange<Int>? {
        guard let search = status?.search else { return nil }
        return max(18, search.ageMin - 5)...min(100, search.ageMax + 5)
    }

    /// «Нравится» ещё можно нажать на экране «собеседник ушёл».
    var canLikeAfterEnd: Bool {
        guard case .ended(_, let reported, _) = phase, !reported else { return false }
        return Date().timeIntervalSince(endedAt) < Self.likeAfterEndWindow
    }

    /// «Далее» — и в разговоре, и на экране «собеседник ушёл».
    func next() {
        guard let mode = currentMode else { return }
        cancelAutoSearch()
        video.endSession()
        join(mode)
    }

    /// «Стоп» / «Выйти из рулетки».
    func stop() {
        guard isInRoulette else { return }
        WebSocketClient.shared.sendRoulette(["type": "roulette.leave"])
        finish()
        Task { await loadStatus() }
    }

    func like() {
        guard let session = activeSession ?? (canLikeAfterEnd ? reportableSession : nil), !liked else { return }
        guard WebSocketClient.shared.sendRoulette(["type": "roulette.like", "sessionId": session.id]) else { return }
        liked = true
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .talking(let session) = phase, session.mode == .text, !text.isEmpty else { return }
        let clientId = UUID().uuidString
        guard WebSocketClient.shared.sendRoulette(["type": "roulette.message", "sessionId": session.id, "text": text, "clientId": clientId]) else {
            notice = String(localized: "Нет подключения к интернету")
            return
        }
        notice = nil
        messages.append(RouletteChatMessage(id: clientId, text: text, isMine: true, createdAt: Date(), isPending: true))
    }

    func userIsTyping() {
        guard case .talking(let session) = phase, session.mode == .text else { return }
        guard Date().timeIntervalSince(lastTypingSentAt) >= Self.typingSendInterval else { return }
        lastTypingSentAt = Date()
        WebSocketClient.shared.sendRoulette(["type": "roulette.typing", "sessionId": session.id])
    }

    /// «Пожаловаться» — во время разговора или на экране «собеседник ушёл».
    func beginReport() {
        guard let session = reportableSession else { return }
        cancelAutoSearch()
        reportTarget = session
    }

    /// Жалоба — на текущего или только что ушедшего собеседника. Сервер сам заканчивает разговор.
    func report(_ session: Session, reason: RouletteReportReason, comment: String?) async -> Bool {
        do {
            try await APIClient.shared.reportRoulette(sessionId: session.id, category: reason.category, comment: comment)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        // Пока жалобу отправляли, человек мог уже уйти из этого разговора (пара, «Стоп») — экран не трогаем.
        guard reportableSession?.id == session.id else { return true }
        video.endSession()
        reportTarget = nil
        showEnded(session, reported: true)
        return true
    }

    /// Жалобу закрыли, не отправив, — отсчёт до следующего поиска начинается заново.
    func resumeAutoSearch() {
        reportTarget = nil
        guard case .ended(let session, let reported, _) = phase, autoSearchTask == nil else { return }
        showEnded(session, reported: reported)
    }

    /// Пожаловаться можно во время разговора и на экране «собеседник ушёл».
    var reportableSession: Session? {
        switch phase {
        case .talking(let session), .ended(let session, _, _): session
        default: nil
        }
    }

    /// Пара открыта в «Чатах» или человек вернулся к выбору режима.
    func closeMatch() {
        finish()
        Task { await loadStatus() }
    }

    // MARK: - События сервера

    private func handle(event: ServerEvent) {
        switch event {
        case .rouletteWaiting(let mode, let cityWait, let expanded, let ageMin, let ageMax):
            // Поиск на экране начинает join(); запоздалое событие (мы уже вышли или разговариваем) экран не меняет.
            guard phase == .searching(mode: mode) else { return }
            cityWaitSeconds = cityWait
            searchExpanded = expanded
            if let ageMin, let ageMax, ageMin <= ageMax { searchAges = ageMin...ageMax }

        case .rouletteMatched(let sessionId, let mode, let peer, let initiator):
            // Собеседник нашёлся, когда мы уже нажали «Стоп» (сообщения разминулись) — сервер должен узнать, что нас нет.
            guard case .searching(let searchingMode) = phase, searchingMode == mode else {
                if activeSession?.id != sessionId { WebSocketClient.shared.sendRoulette(["type": "roulette.leave"]) }
                return
            }
            cancelAutoSearch()
            messages = []
            liked = false
            peerTypingUntil = nil
            notice = nil
            phase = .talking(Session(id: sessionId, mode: mode, peer: peer, startedAt: Date()))
            if mode == .video { video.beginSession(id: sessionId, initiator: initiator) }

        case .rouletteEnded(let sessionId, let reason, let matchId, _):
            guard let session = activeSession, session.id == sessionId else { return }
            video.endSession()
            if reason == "matched", let matchId {
                // Камера на экране пары не нужна; «Продолжить рулетку» включит её снова.
                video.stop()
                phase = .matched(session, match: recentMatches[matchId])
                if recentMatches[matchId] == nil { Task { await loadMatch(id: matchId, for: session) } }
            } else {
                showEnded(session, reported: false)
            }

        case .roulettePaired(let sessionId, let matchId, _):
            // Ещё на экране «собеседник ушёл» этого разговора — показываем пару; уже с другим — только подсказка.
            if case .ended(let session, _, _) = phase, session.id == sessionId {
                cancelAutoSearch()
                video.stop()
                phase = .matched(session, match: recentMatches[matchId])
                if recentMatches[matchId] == nil { Task { await loadMatch(id: matchId, for: session) } }
            } else if isInRoulette {
                notice = String(localized: "Симпатия из прошлого разговора взаимна — пара уже в «Чатах»")
            }

        case .datingMatch(let match):
            recentMatches[match.id] = match
            if case .matched(let session, nil) = phase { phase = .matched(session, match: match) }

        case .rouletteLiked(let sessionId):
            if reportableSession?.id == sessionId { liked = true }

        case .rouletteMessage(let sessionId, let message):
            guard activeSession?.id == sessionId else { return }
            peerTypingUntil = nil
            messages.append(RouletteChatMessage(id: message.id, text: message.text, isMine: false, createdAt: message.createdAt, isPending: false))

        case .rouletteMessageAck(let sessionId, let clientId, let message):
            guard activeSession?.id == sessionId, let index = messages.firstIndex(where: { $0.id == clientId }) else { return }
            messages[index].id = message.id
            messages[index].createdAt = message.createdAt
            messages[index].isPending = false

        case .rouletteTyping(let sessionId):
            if activeSession?.id == sessionId { peerTypingUntil = Date().addingTimeInterval(Self.typingVisibleFor) }

        case .rouletteError(let code, let message, let clientId, _):
            handleError(code: code, message: message, clientId: clientId)

        default:
            break
        }
    }

    private func handleError(code: String, message: String, clientId: String?) {
        if let clientId {
            // Сообщение не прошло (контакты, стоп-слово, лимит) — убираем его и объясняем почему.
            messages.removeAll { $0.id == clientId }
            notice = message
            return
        }
        if code == "RATE_LIMITED" {
            notice = message
            return
        }
        // Нельзя в рулетку (запрет, нет проверки селфи, анкета ограничена…) — назад к выбору режима.
        finish()
        errorMessage = message
        Task { await loadStatus() }
    }

    private var activeSession: Session? {
        switch phase {
        case .talking(let session): session
        default: nil
        }
    }

    private var currentMode: RouletteMode? {
        switch phase {
        case .idle: nil
        case .searching(let mode): mode
        case .talking(let session), .ended(let session, _, _), .matched(let session, _): session.mode
        }
    }

    private func join(_ mode: RouletteMode) {
        guard WebSocketClient.shared.sendRoulette(["type": "roulette.join", "mode": mode.rawValue]) else {
            finish()
            errorMessage = String(localized: "Нет подключения к интернету")
            return
        }
        searchStartedAt = Date()
        searchExpanded = false
        searchAges = status?.search.map { $0.ageMin...$0.ageMax }
        phase = .searching(mode: mode)
    }

    private func showEnded(_ session: Session, reported: Bool) {
        cancelAutoSearch()
        let at = Date().addingTimeInterval(Self.autoSearchDelay)
        if case .talking = phase { endedAt = Date() }
        phase = .ended(session, reported: reported, autoSearchAt: at)
        // Жалоба ещё открыта — отсчёт начнётся, когда её закроют (resumeAutoSearch).
        guard reportTarget == nil else { return }
        autoSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoSearchDelay))
            guard !Task.isCancelled, let self, case .ended(let ended, _, _) = self.phase, ended.id == session.id else { return }
            self.next()
        }
    }

    /// Карточка пары не пришла по сокету (например, сокет переподключался) — берём её из списка пар.
    private func loadMatch(id: String, for session: Session) async {
        guard let match = try? await APIClient.shared.fetchMatches().first(where: { $0.id == id }) else { return }
        if case .matched(let current, nil) = phase, current.id == session.id { phase = .matched(session, match: match) }
    }

    private func cancelAutoSearch() {
        autoSearchTask?.cancel()
        autoSearchTask = nil
    }

    private func finish() {
        cancelAutoSearch()
        reportTarget = nil
        video.stop()
        messages = []
        liked = false
        peerTypingUntil = nil
        phase = .idle
    }
}
