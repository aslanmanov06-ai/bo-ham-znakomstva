import Foundation

/// Коды отказов, на которые знакомства реагируют отдельным экраном, а не просто текстом ошибки.
enum ServerErrorCode {
    /// Не приняты действующие правила сообщества.
    static let termsNotAccepted = "TERMS_NOT_ACCEPTED"
    /// Лайки и первые сообщения — только с подтверждённой селфи анкетой.
    static let verificationRequired = "VERIFICATION_REQUIRED"
    /// Отмечено «мы нашли друг друга»: лента и лайки закрыты, пока пара не вернётся к поиску.
    static let inCouple = "IN_COUPLE"
    /// Незнакомому напрямую не написать — только запросом на переписку.
    static let chatRequestRequired = "CHAT_REQUEST_REQUIRED"
    /// Без анкеты с фото нельзя искать людей, писать незнакомым и знакомиться.
    static let profileRequired = "PROFILE_REQUIRED"
}

/// Запросы знакомств, безопасности, жалоб и правил сообщества. Вынесены из APIClient.swift, чтобы
/// он не рос: общий транспорт (токен, обновление сессии, разбор ошибок) остаётся в `request`.
extension APIClient {
    // MARK: - Правила сообщества

    /// Без авторизации: правила показываются и до входа.
    func fetchCommunityRules() async throws -> CommunityRules {
        try await request(path: "/legal/rules", method: "GET", body: nil as String?, authorized: false)
    }

    /// Версия — та, которую показали пользователю: «принять» можно только прочитанный текст.
    func acceptCommunityRules(version: String) async throws {
        let _: EmptyResponse = try await request(path: "/legal/rules/accept", method: "POST", body: ["version": version], authorized: true)
    }

    // MARK: - Анкета

    func fetchDatingCatalog() async throws -> DatingCatalog {
        try await request(path: "/dating/catalog", method: "GET", body: nil as String?, authorized: true)
    }

    func fetchMyDatingProfile() async throws -> MyDatingProfile {
        try await request(path: "/dating/profile/me", method: "GET", body: nil as String?, authorized: true)
    }

    func updateMyDatingProfile(_ update: DatingProfileUpdate) async throws -> MyDatingProfile {
        try await request(path: "/dating/profile/me", method: "PATCH", body: update, authorized: true)
    }

    /// Весь набор фото целиком: порядок в массиве — порядок в анкете, первое фото главное.
    func setDatingPhotos(attachmentIds: [String]) async throws -> MyDatingProfile {
        try await request(path: "/dating/profile/me/photos", method: "PUT", body: ["attachmentIds": attachmentIds], authorized: true)
    }

    func setDatingVideo(attachmentId: String) async throws -> MyDatingProfile {
        try await request(path: "/dating/profile/me/video", method: "PUT", body: ["attachmentId": attachmentId], authorized: true)
    }

    func removeDatingVideo() async throws -> MyDatingProfile {
        try await request(path: "/dating/profile/me/video", method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Своя анкета глазами других — предпросмотр перед публикацией.
    func fetchMyDatingPreview() async throws -> DatingProfilePublic {
        try await request(path: "/dating/profiles/me/preview", method: "GET", body: nil as String?, authorized: true)
    }

    func fetchDatingProfile(userId: String) async throws -> DatingProfilePublic {
        try await request(path: "/dating/profiles/\(userId)", method: "GET", body: nil as String?, authorized: true)
    }

    /// Геопозиция нужна только для расстояния в ленте; сами координаты сервер обратно не отдаёт.
    func setDatingLocation(latitude: Double, longitude: Double) async throws -> MyDatingProfile {
        let body = DatingLocationBody(latitude: latitude, longitude: longitude)
        return try await request(path: "/dating/location", method: "PUT", body: body, authorized: true)
    }

    func clearDatingLocation() async throws -> MyDatingProfile {
        try await request(path: "/dating/location", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Подтверждение селфи

    func fetchVerificationStatus() async throws -> VerificationStatus {
        try await request(path: "/dating/verification", method: "GET", body: nil as String?, authorized: true)
    }

    func submitSelfie(attachmentId: String) async throws -> VerificationStatus {
        try await request(path: "/dating/verification", method: "POST", body: ["attachmentId": attachmentId], authorized: true)
    }

    // MARK: - Лента и настройки поиска

    func fetchSearchSettings() async throws -> DatingSearchSettings {
        try await request(path: "/dating/search-settings", method: "GET", body: nil as String?, authorized: true)
    }

    func updateSearchSettings(_ settings: DatingSearchSettings) async throws -> DatingSearchSettings {
        try await request(path: "/dating/search-settings", method: "PATCH", body: settings, authorized: true)
    }

    /// Страница сетки всех анкет. cursor — nextCursor предыдущей страницы, nil — первая страница.
    func browseDatingProfiles(filters: DatingBrowseFilters, cursor: String?) async throws -> DatingBrowsePage {
        var components = URLComponents()
        components.path = "/dating/browse"
        var items = filters.queryItems
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items.isEmpty ? nil : items
        return try await request(path: components.string ?? "/dating/browse", method: "GET", body: nil as String?, authorized: true)
    }

    func fetchDatingFeed() async throws -> DatingFeed {
        try await request(path: "/dating/feed", method: "GET", body: nil as String?, authorized: true)
    }

    /// Анкета по точному @username (без «@»). Пустой список — не нашли или человек запретил такой поиск.
    func searchDatingProfiles(username: String) async throws -> [DatingFeedCard] {
        let result: DatingUsernameSearch = try await request(
            path: "/dating/search?username=\(Self.encodeQueryValue(username))", method: "GET", body: nil as String?, authorized: true
        )
        return result.cards
    }

    func swipe(userId: String, action: SwipeAction) async throws -> SwipeResult {
        let body = SwipeBody(userId: userId, action: action)
        return try await request(path: "/dating/swipes", method: "POST", body: body, authorized: true)
    }

    // MARK: - Пары

    func fetchMatches() async throws -> [DatingMatch] {
        try await request(path: "/dating/matches", method: "GET", body: nil as String?, authorized: true)
    }

    /// Удаляет пару вместе с её чатом у обоих — заново эта пара не возникнет.
    func unmatch(matchId: String) async throws {
        let _: EmptyResponse = try await request(path: "/dating/matches/\(matchId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Первые сообщения

    func fetchIntros() async throws -> IntroInbox {
        try await request(path: "/dating/intros", method: "GET", body: nil as String?, authorized: true)
    }

    /// Ответ на первое сообщение создаёт пару: переписка продолжается в её чате.
    func replyToIntro(introId: String, text: String) async throws -> DatingMatch {
        let response: IntroReplyResponse = try await request(
            path: "/dating/intros/\(introId)/reply", method: "POST", body: ["text": text], authorized: true
        )
        return response.match
    }

    func declineIntro(introId: String) async throws {
        let _: EmptyResponse = try await request(path: "/dating/intros/\(introId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Запросы на переписку

    /// Написать незнакомому: видимой анкете нужного пола — первым сообщением знакомств, остальным — запросом.
    func sendChatRequest(userId: String, text: String) async throws -> SendChatRequestResult {
        let body = SendIntroBody(userId: userId, text: text)
        return try await request(path: "/chat-requests", method: "POST", body: body, authorized: true)
    }

    /// Общий ящик «Запросы»: и первые сообщения знакомств, и обычные запросы.
    func fetchChatRequests() async throws -> ChatRequestInbox {
        try await request(path: "/chat-requests", method: "GET", body: nil as String?, authorized: true)
    }

    /// Ответ открывает личный чат. На первое сообщение отвечаем через знакомства — там заодно создаётся пара.
    /// nil — пара возникла, но её чат уже удалён.
    func replyToChatRequest(_ incoming: IncomingChatRequest, text: String) async throws -> String? {
        switch incoming.kind {
        case .intro:
            return try await replyToIntro(introId: incoming.id, text: text).chatId
        case .request:
            let reply: ChatRequestReply = try await request(
                path: "/chat-requests/\(incoming.id)/reply", method: "POST", body: ["text": text], authorized: true
            )
            return reply.chatId
        }
    }

    func declineChatRequest(_ incoming: IncomingChatRequest) async throws {
        switch incoming.kind {
        case .intro:
            try await declineIntro(introId: incoming.id)
        case .request:
            let _: EmptyResponse = try await request(path: "/chat-requests/\(incoming.id)", method: "DELETE", body: nil as String?, authorized: true)
        }
    }

    // MARK: - «Путь к браку»

    func fetchJourney(matchId: String) async throws -> JourneyView {
        try await request(path: "/dating/matches/\(matchId)/journey", method: "GET", body: nil as String?, authorized: true)
    }

    /// Предложить ступень; если её уже предложил второй — это согласие, и ступень подтверждается.
    func proposeJourneyStage(matchId: String, stage: String) async throws -> JourneyView {
        try await request(path: "/dating/matches/\(matchId)/journey/stage", method: "POST", body: ["stage": stage], authorized: true)
    }

    func dropJourneyStageProposal(matchId: String) async throws -> JourneyView {
        try await request(path: "/dating/matches/\(matchId)/journey/stage", method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Все свои отмеченные пункты чек-листа целиком: снятая галочка — пункт, которого нет в списке.
    func setJourneyChecklist(matchId: String, items: [String]) async throws -> JourneyView {
        try await request(path: "/dating/matches/\(matchId)/journey/checklist", method: "PUT", body: ["items": items], authorized: true)
    }

    /// «Вернуться к поиску»: снимает «мы нашли друг друга» с обоих.
    func leaveCouple() async throws {
        let _: EmptyResponse = try await request(path: "/dating/couple", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Встречи

    func fetchMeetings(matchId: String) async throws -> [DatingMeeting] {
        try await request(path: "/dating/matches/\(matchId)/meetings", method: "GET", body: nil as String?, authorized: true)
    }

    func proposeMeeting(matchId: String, startsAt: Date, place: String, note: String?) async throws -> DatingMeeting {
        let body = MeetingBody(startsAt: startsAt, place: place, note: note)
        return try await request(path: "/dating/matches/\(matchId)/meetings", method: "POST", body: body, authorized: true)
    }

    func acceptMeeting(meetingId: String) async throws -> DatingMeeting {
        try await request(path: "/dating/meetings/\(meetingId)/accept", method: "POST", body: nil as String?, authorized: true)
    }

    func declineMeeting(meetingId: String) async throws -> DatingMeeting {
        try await request(path: "/dating/meetings/\(meetingId)/decline", method: "POST", body: nil as String?, authorized: true)
    }

    /// Предложить другое время вместо полученного приглашения.
    func rescheduleMeeting(meetingId: String, startsAt: Date, place: String?, note: String?) async throws -> DatingMeeting {
        let body = MeetingBody(startsAt: startsAt, place: place, note: note)
        return try await request(path: "/dating/meetings/\(meetingId)/reschedule", method: "POST", body: body, authorized: true)
    }

    func cancelMeeting(meetingId: String) async throws -> DatingMeeting {
        try await request(path: "/dating/meetings/\(meetingId)/cancel", method: "POST", body: nil as String?, authorized: true)
    }

    /// Отправляет место и время встречи доверенным контактам; возвращает, скольким ушло.
    func shareMeeting(meetingId: String) async throws -> Int {
        let response: MeetingShareResponse = try await request(
            path: "/dating/meetings/\(meetingId)/share", method: "POST", body: nil as String?, authorized: true
        )
        return response.sharedWith
    }

    // MARK: - Безопасность

    func fetchTrustedContacts() async throws -> [User] {
        try await request(path: "/safety/contacts", method: "GET", body: nil as String?, authorized: true)
    }

    func addTrustedContact(userId: String) async throws {
        let _: EmptyResponse = try await request(path: "/safety/contacts/\(userId)", method: "PUT", body: nil as String?, authorized: true)
    }

    func removeTrustedContact(userId: String) async throws {
        let _: EmptyResponse = try await request(path: "/safety/contacts/\(userId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Тревога: геопозиция уходит доверенным контактам и модераторам. Повторный вызов обновляет открытую тревогу.
    func raiseSos(latitude: Double, longitude: Double, accuracyM: Double?, note: String?, withUserId: String?) async throws -> SosRaised {
        let body = RaiseSosBody(latitude: latitude, longitude: longitude, accuracyM: accuracyM, note: note, withUserId: withUserId)
        return try await request(path: "/safety/sos", method: "POST", body: body, authorized: true)
    }

    func updateSosLocation(alertId: String, latitude: Double, longitude: Double, accuracyM: Double?) async throws -> SosAlert {
        let body = SosLocationBody(latitude: latitude, longitude: longitude, accuracyM: accuracyM)
        return try await request(path: "/safety/sos/\(alertId)/location", method: "PATCH", body: body, authorized: true)
    }

    /// Тревога, открытая тем, кто добавил вас в доверенные контакты: приходит по push с sosId.
    func fetchSosAlert(alertId: String) async throws -> SosAlert {
        try await request(path: "/safety/sos/\(alertId)", method: "GET", body: nil as String?, authorized: true)
    }

    func closeSos(alertId: String) async throws -> SosAlert {
        try await request(path: "/safety/sos/\(alertId)/close", method: "POST", body: nil as String?, authorized: true)
    }

    // MARK: - Жалобы

    func reportUser(userId: String, category: ReportCategory, comment: String?, messageId: String? = nil) async throws {
        let body = ReportBody(userId: userId, category: category, comment: comment, messageId: messageId)
        let _: EmptyResponse = try await request(path: "/reports", method: "POST", body: body, authorized: true)
    }
}

private struct DatingLocationBody: Encodable {
    let latitude: Double
    let longitude: Double
}

private struct SwipeBody: Encodable {
    let userId: String
    let action: SwipeAction
}

private struct SendIntroBody: Encodable {
    let userId: String
    let text: String
}

private struct IntroReplyResponse: Decodable {
    let match: DatingMatch
}

/// place у переноса встречи необязателен (nil — оставить прежнее место), поэтому nil не отправляется.
private struct MeetingBody: Encodable {
    let startsAt: Date
    let place: String?
    let note: String?
}

private struct MeetingShareResponse: Decodable {
    let sharedWith: Int
}

private struct RaiseSosBody: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double?
    let note: String?
    let withUserId: String?
}

private struct SosLocationBody: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double?
}

private struct ReportBody: Encodable {
    let userId: String
    let category: ReportCategory
    let comment: String?
    let messageId: String?
}
