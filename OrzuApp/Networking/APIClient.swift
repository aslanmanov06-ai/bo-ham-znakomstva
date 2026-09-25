import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case server(String)
    /// Отказ с машинным кодом (см. ServerErrorCode): по нему экран знакомств решает, что показать.
    case rejected(code: String, message: String)
    case invalidResponse
    /// До сервера не достучаться: нет сети, обрыв, таймаут.
    case offline
    /// Сервер ответил 5xx (перезапуск, перегрузка) — запрос стоит повторить позже.
    case unavailable(status: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Сессия истекла, войдите заново"
        case .server(let message): return message
        case .rejected(_, let message): return message
        case .invalidResponse: return "Некорректный ответ сервера"
        case .offline: return "Нет подключения к интернету"
        case .unavailable(let status): return "Сервер временно недоступен (\(status)), попробуйте позже"
        }
    }

    /// Сбой связи, а не отказ сервера: можно показать сохранённые данные и повторить запрос позже.
    var isTransient: Bool {
        switch self {
        case .offline, .unavailable: return true
        default: return false
        }
    }

    var code: String? {
        if case .rejected(let code, _) = self { return code }
        return nil
    }
}

extension Notification.Name {
    /// Refresh-токен отклонён сервером: сессия закончилась, токены очищены.
    static let sessionExpired = Notification.Name("com.orzuapp.messenger.sessionExpired")
}

actor APIClient {
    static let shared = APIClient()

    /// Без сети iOS по умолчанию ждёт ответа до 60 с — столько же висел бы экран, прежде чем показать сохранённое.
    /// Это таймаут тишины между пакетами, а не всего запроса, поэтому большие загрузки он не обрывает.
    private static let requestTimeout: TimeInterval = 20

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = APIClient.requestTimeout
        return URLSession(configuration: configuration)
    }()
    /// Последние ответы на GET-запросы: из них экраны открываются без сети.
    private let responseCache = DiskStore(name: "ResponseCache", base: .applicationSupportDirectory)
    private var refreshTask: Task<Void, Error>?

    private lazy var encoder = ISO8601Coding.makeEncoder()
    private lazy var decoder = ISO8601Coding.makeDecoder()

    private init() {}

    // MARK: - Public API

    /// Первый шаг регистрации: сервер шлёт 6-значный код на почту. Занятые почта и username отклоняются
    /// сразу — ServerErrorCode.emailTaken / .usernameTaken.
    func requestRegistrationCode(email: String, username: String) async throws {
        let body = ["email": email, "username": username]
        let _: EmptyResponse = try await request(path: "/auth/register/code", method: "POST", body: body, authorized: false)
    }

    func register(username: String, displayName: String, password: String, email: String, phone: String, code: String) async throws -> AuthResponse {
        let body = ["username": username, "displayName": displayName, "password": password, "email": email, "phone": phone, "code": code]
        let response: AuthResponse = try await request(path: "/auth/register", method: "POST", body: body, authorized: false)
        TokenStore.shared.save(tokens: response.tokens)
        return response
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        let body = ["username": username, "password": password]
        let response: AuthResponse = try await request(path: "/auth/login", method: "POST", body: body, authorized: false)
        TokenStore.shared.save(tokens: response.tokens)
        return response
    }

    func googleSignIn(idToken: String) async throws -> GoogleSignInResponse {
        let response: GoogleSignInResponse = try await request(path: "/auth/google", method: "POST", body: ["idToken": idToken], authorized: false)
        if case .authenticated(let auth) = response {
            TokenStore.shared.save(tokens: auth.tokens)
        }
        return response
    }

    /// Код уходит на почту из Google; `email` сервер учитывает, только если Google почту не передал.
    func requestGoogleRegistrationCode(registrationToken: String, username: String, email: String?) async throws {
        var body = ["registrationToken": registrationToken, "username": username]
        body["email"] = email
        let _: EmptyResponse = try await request(path: "/auth/google/register/code", method: "POST", body: body, authorized: false)
    }

    func completeGoogleRegistration(
        registrationToken: String, username: String, displayName: String, email: String?, phone: String, code: String
    ) async throws -> AuthResponse {
        var body = ["registrationToken": registrationToken, "username": username, "displayName": displayName, "phone": phone, "code": code]
        body["email"] = email
        let response: AuthResponse = try await request(path: "/auth/google/register", method: "POST", body: body, authorized: false)
        TokenStore.shared.save(tokens: response.tokens)
        return response
    }

    func logout() async {
        if let refreshToken = TokenStore.shared.refreshToken {
            let _: EmptyResponse? = try? await request(path: "/auth/logout", method: "POST", body: ["refreshToken": refreshToken], authorized: false)
        }
        TokenStore.shared.clear()
    }

    func me() async throws -> User {
        try await request(path: "/auth/me", method: "GET", body: nil as String?, authorized: true)
    }

    func fetchChats() async throws -> [Chat] {
        try await request(path: Self.chatsPath, method: "GET", body: nil as String?, authorized: true)
    }

    /// Список чатов с прошлого раза — показать сразу, не дожидаясь сети.
    func cachedChats() -> [Chat]? {
        cachedResponse(path: Self.chatsPath)
    }

    /// POST /chats и /chats/channel возвращают "сырой" объект чата без participants/lastMessage —
    /// в отличие от GET /chats, где список уже обогащён. ChatSummary отражает этот более узкий контракт.
    func createChat(userId: String) async throws -> ChatSummary {
        try await request(path: "/chats", method: "POST", body: ["userId": userId], authorized: true)
    }

    func createChannel(title: String, username: String) async throws -> ChatSummary {
        let body = CreateChannelRequest(title: title, username: username)
        return try await request(path: "/chats/channel", method: "POST", body: body, authorized: true)
    }

    func searchChannels(query: String) async throws -> [PublicChannel] {
        try await request(path: "/chats/channels/search?q=\(Self.encodeQueryValue(query))", method: "GET", body: nil as String?, authorized: true)
    }

    func subscribeToChannel(chatId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/subscribe", method: "POST", body: nil as String?, authorized: true)
    }

    func fetchMessages(chatId: String, before: Date? = nil) async throws -> [Message] {
        var path = Self.messagesPath(chatId: chatId)
        if let before {
            path += "?before=\(ISO8601Coding.string(from: before))"
        }
        return try await request(path: path, method: "GET", body: nil as String?, authorized: true)
    }

    /// Последние сообщения чата с прошлого открытия.
    func cachedMessages(chatId: String) -> [Message]? {
        cachedResponse(path: Self.messagesPath(chatId: chatId))
    }

    /// clientMessageId одинаков во всех повторах одного сообщения — сервер не создаст дубль, если первый ответ потерялся.
    func sendMessage(
        chatId: String,
        text: String,
        attachmentId: String?,
        encrypted: EncryptedPayload? = nil,
        viewTimerSec: Int? = nil,
        replyToId: String? = nil,
        clientMessageId: String
    ) async throws -> Message {
        let body = SendMessageBody(
            text: text,
            attachmentId: attachmentId,
            ciphertext: encrypted?.ciphertext,
            senderKey: encrypted?.senderKey,
            viewTimerSec: viewTimerSec,
            replyToId: replyToId,
            clientMessageId: clientMessageId
        )
        return try await request(path: "/chats/\(chatId)/messages", method: "POST", body: body, authorized: true)
    }

    /// Переслать сообщения (свои или чужие) в другой чат. Сервер создаёт по новому сообщению на каждое и возвращает их.
    func forwardMessages(toChatId: String, messageIds: [String]) async throws -> [Message] {
        let body = ForwardMessagesBody(messageIds: messageIds)
        return try await request(path: "/chats/\(toChatId)/messages/forward", method: "POST", body: body, authorized: true)
    }

    /// Поиск по тексту сообщений чата: от 2 символов, новые первыми, не больше 50 (лимиты backend).
    func searchMessages(chatId: String, query: String) async throws -> [Message] {
        let path = "/chats/\(chatId)/messages/search?q=\(Self.encodeQueryValue(query))"
        return try await request(path: path, method: "GET", body: nil as String?, authorized: true)
    }

    func editMessage(chatId: String, messageId: String, text: String, encrypted: EncryptedPayload? = nil) async throws -> Message {
        var body = ["text": text]
        body["ciphertext"] = encrypted?.ciphertext
        body["senderKey"] = encrypted?.senderKey
        return try await request(path: "/chats/\(chatId)/messages/\(messageId)", method: "PATCH", body: body, authorized: true)
    }

    /// forEveryone: false — сообщение пропадёт только у текущего пользователя.
    func deleteMessage(chatId: String, messageId: String, forEveryone: Bool) async throws {
        let path = "/chats/\(chatId)/messages/\(messageId)?forEveryone=\(forEveryone)"
        let _: EmptyResponse = try await request(path: path, method: "DELETE", body: nil as String?, authorized: true)
    }

    /// emoji = nil — снять свою реакцию.
    func setReaction(chatId: String, messageId: String, emoji: String?) async throws -> Message {
        let path = "/chats/\(chatId)/messages/\(messageId)/reaction"
        if let emoji {
            return try await request(path: path, method: "PUT", body: ["emoji": emoji], authorized: true)
        }
        return try await request(path: path, method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Первое открытие фото с таймером запускает отсчёт на сервере; повторное возвращает те же отметки.
    func openTimedPhoto(chatId: String, messageId: String) async throws -> TimedPhotoOpening {
        try await request(path: "/chats/\(chatId)/messages/\(messageId)/open", method: "POST", body: nil as String?, authorized: true)
    }

    /// Закрепить чат вверху своего списка. Закреплённых не больше пяти — сверх этого сервер отвечает ошибкой.
    func pinChat(chatId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/pin", method: "PUT", body: nil as String?, authorized: true)
    }

    func unpinChat(chatId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/pin", method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Закреплённое сообщение одно на чат и видно всем участникам. messageId = nil — открепить.
    func pinMessage(chatId: String, messageId: String?) async throws {
        let path = "/chats/\(chatId)/pinned-message"
        if let messageId {
            let _: EmptyResponse = try await request(path: path, method: "PUT", body: ["messageId": messageId], authorized: true)
        } else {
            let _: EmptyResponse = try await request(path: path, method: "DELETE", body: nil as String?, authorized: true)
        }
    }

    /// forEveryone: false — переписка пропадёт только у текущего пользователя (на всех его устройствах).
    func clearHistory(chatId: String, forEveryone: Bool) async throws {
        let body = ClearHistoryBody(forEveryone: forEveryone)
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/clear", method: "POST", body: body, authorized: true)
    }

    /// Удаляет личный или секретный чат вместе с перепиской у обоих. Из группы и канала выходят (removeMember).
    func deleteChat(chatId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    func markRead(chatId: String, messageId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/messages/read", method: "POST", body: ["messageId": messageId], authorized: true)
    }

    // MARK: - Профиль и приватность

    func fetchSettings() async throws -> AccountSettings {
        try await request(path: "/users/me/settings", method: "GET", body: nil as String?, authorized: true)
    }

    func updateProfile(displayName: String) async throws -> AccountSettings {
        try await request(path: "/users/me/profile", method: "PATCH", body: ["displayName": displayName], authorized: true)
    }

    func updateUsername(_ username: String) async throws -> AccountSettings {
        try await request(path: "/users/me/username", method: "PATCH", body: ["username": username], authorized: true)
    }

    func updatePrivacy(_ update: PrivacyUpdate) async throws -> AccountSettings {
        try await request(path: "/users/me/privacy", method: "PATCH", body: update, authorized: true)
    }

    /// avatarUrl с сервера — путь вида /users/<id>/avatar?v=<версия>, доступный только с токеном.
    func downloadAvatar(path: String) async throws -> Data {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = "GET"
        return try await send(request, authorized: true)
    }

    /// Все данные аккаунта одним JSON — отдаётся как есть, без разбора: человек сохраняет его файлом.
    func exportMyData() async throws -> Data {
        var request = URLRequest(url: makeURL(path: "/users/me/export"))
        request.httpMethod = "GET"
        return try await send(request, authorized: true)
    }

    func fetchBlockedUsers() async throws -> [User] {
        try await request(path: "/users/me/blocked", method: "GET", body: nil as String?, authorized: true)
    }

    func blockUser(id: String) async throws {
        let _: EmptyResponse = try await request(path: "/users/me/blocked/\(id)", method: "PUT", body: nil as String?, authorized: true)
    }

    func unblockUser(id: String) async throws {
        let _: EmptyResponse = try await request(path: "/users/me/blocked/\(id)", method: "DELETE", body: nil as String?, authorized: true)
    }

    func requestEmailVerification(email: String) async throws {
        let _: EmptyResponse = try await request(path: "/users/me/email", method: "POST", body: ["email": email], authorized: true)
    }

    func verifyEmail(code: String) async throws -> AccountSettings {
        try await request(path: "/users/me/email/verify", method: "POST", body: ["code": code], authorized: true)
    }

    func removeEmail() async throws -> AccountSettings {
        try await request(path: "/users/me/email", method: "DELETE", body: nil as String?, authorized: true)
    }

    /// Сервер гасит все сессии и выдаёт новые токены этому устройству. current == nil — пароля ещё нет (аккаунт из Google).
    func changePassword(current: String?, new: String) async throws {
        var body = ["newPassword": new]
        body["currentPassword"] = current
        let tokens: AuthTokens = try await request(path: "/auth/change-password", method: "POST", body: body, authorized: true)
        TokenStore.shared.save(tokens: tokens)
    }

    func logoutEverywhere() async throws {
        let _: EmptyResponse = try await request(path: "/auth/logout-all", method: "POST", body: nil as String?, authorized: true)
        TokenStore.shared.clear()
    }

    func requestPasswordReset(email: String) async throws {
        let _: EmptyResponse = try await request(path: "/auth/password-reset/request", method: "POST", body: ["email": email], authorized: false)
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        let body = ["email": email, "code": code, "newPassword": newPassword]
        let _: EmptyResponse = try await request(path: "/auth/password-reset/confirm", method: "POST", body: body, authorized: false)
    }

    // MARK: - Секретные чаты

    func createSecretChat(userId: String) async throws -> ChatSummary {
        try await request(path: "/chats/secret", method: "POST", body: ["userId": userId], authorized: true)
    }

    func uploadE2EKey(publicKey: String) async throws {
        let _: EmptyResponse = try await request(path: "/users/me/e2e-key", method: "PUT", body: ["publicKey": publicKey], authorized: true)
    }

    func fetchE2EKey(userId: String) async throws -> String {
        let response: E2EKeyResponse = try await request(path: "/users/\(userId)/e2e-key", method: "GET", body: nil as String?, authorized: true)
        return response.publicKey
    }

    // MARK: - Боты

    func fetchMyBots() async throws -> [Bot] {
        try await request(path: "/bots", method: "GET", body: nil as String?, authorized: true)
    }

    func createBot(username: String, displayName: String) async throws -> Bot {
        try await request(path: "/bots", method: "POST", body: ["username": username, "displayName": displayName], authorized: true)
    }

    func regenerateBotToken(botId: String) async throws -> String {
        let response: BotTokenResponse = try await request(path: "/bots/\(botId)/token", method: "POST", body: nil as String?, authorized: true)
        return response.token
    }

    func deleteBot(botId: String) async throws {
        let _: EmptyResponse = try await request(path: "/bots/\(botId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    func fetchChatDetail(chatId: String) async throws -> ChatDetail {
        try await request(path: "/chats/\(chatId)", method: "GET", body: nil as String?, authorized: true)
    }

    func addMember(chatId: String, userId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/members", method: "POST", body: ["userId": userId], authorized: true)
    }

    func updateMemberRole(chatId: String, userId: String, role: ParticipantRole) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/members/\(userId)", method: "PATCH", body: ["role": role.rawValue], authorized: true)
    }

    func removeMember(chatId: String, userId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/members/\(userId)", method: "DELETE", body: nil as String?, authorized: true)
    }

    func searchUsers(query: String) async throws -> [User] {
        try await request(path: "/users/search?q=\(Self.encodeQueryValue(query))", method: "GET", body: nil as String?, authorized: true)
    }

    /// makeURL уже режет path по "?" и передаёт хвост как percentEncodedQuery как есть — значит value
    /// нужно закодировать самим, причём вычеркнув из urlQueryAllowed "&=+#": иначе они в самом
    /// поисковом запросе ломают разбор query-строки (двойное кодирование, наоборот, тоже не нужно).
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Calls

    func fetchIceServers() async throws -> [IceServer] {
        let response: IceServersResponse = try await request(path: "/calls/ice-servers", method: "GET", body: nil as String?, authorized: true)
        return response.iceServers
    }

    // MARK: - Push

    /// kind: "ALERT" — обычные уведомления, "VOIP" — PushKit-токен для входящих звонков.
    func registerDevice(token: String, kind: String = "ALERT") async throws {
        let _: EmptyResponse = try await request(path: "/devices", method: "POST", body: ["token": token, "kind": kind], authorized: true)
    }

    func unregisterDevice(token: String) async throws {
        let _: EmptyResponse = try await request(path: "/devices/\(token)", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Attachments

    /// mediaKind — только .voice или .videoNote: их сервер по mime не отличит от обычного файла.
    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        mediaKind: AttachmentKind? = nil,
        durationSec: Int? = nil
    ) async throws -> Attachment {
        var fields: [String: String] = [:]
        fields["kind"] = mediaKind?.rawValue
        fields["durationSec"] = durationSec.map(String.init)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: makeURL(path: "/attachments"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary, fields: fields, fieldName: "file", fileName: fileName, mimeType: mimeType, data: data
        )

        let responseData = try await send(request, authorized: true)
        return try decoder.decode(Attachment.self, from: responseData)
    }

    func downloadAttachment(id: String) async throws -> Data {
        var request = URLRequest(url: makeURL(path: "/attachments/\(id)"))
        request.httpMethod = "GET"
        return try await send(request, authorized: true)
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String] = [:],
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) -> Data {
        // Кавычки и переводы строк в имени сломали бы заголовок part'а.
        let safeFileName = fileName.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var body = Data()
        // Имена и значения полей задаём сами (kind, durationSec) — экранировать нечего.
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeFileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    // MARK: - Core request

    /// Не private: этим же методом пользуются запросы знакомств из APIClient+Dating.swift.
    func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        authorized: Bool
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let cacheKey = method == "GET" && authorized && Self.isCacheable(path: path) ? path : nil
        let data: Data
        do {
            data = try await send(request, authorized: authorized)
        } catch let error as APIError where error.isTransient {
            guard let cacheKey, let cached = responseCache.load(cacheKey) else { throw error }
            return try decoder.decode(Response.self, from: cached)
        }
        // Пока шёл запрос, человек мог выйти — его данные не должны остаться на устройстве.
        if let cacheKey, TokenStore.shared.accessToken != nil {
            responseCache.save(data, for: cacheKey)
        }
        // Пустое тело (например 204) — Response в этом случае EmptyResponse.
        return try decoder.decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }

    /// Сохранённый ответ на GET без обращения к сети. Не разобрался (формат поменялся с обновлением) — выбрасываем.
    private func cachedResponse<Response: Decodable>(path: String) -> Response? {
        guard let data = responseCache.load(path) else { return nil }
        guard let response = try? decoder.decode(Response.self, from: data) else {
            responseCache.remove(path)
            return nil
        }
        return response
    }

    nonisolated func clearResponseCache() {
        responseCache.removeAll()
    }

    /// Поиск (?q=, ?username=) и следующие страницы (?before= в истории, ?cursor= в сетке анкет) офлайн бесполезны, а каждый новый запрос дал бы новый файл.
    static func isCacheable(path: String) -> Bool {
        guard let query = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return true }
        let names = query.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "" }
        return !names.contains("q") && !names.contains("before") && !names.contains("username") && !names.contains("cursor")
    }

    private static let chatsPath = "/chats"

    private static func messagesPath(chatId: String) -> String {
        "/chats/\(chatId)/messages"
    }

    /// Единая точка отправки: подставляет токен, на 401 один раз обновляет его и повторяет запрос.
    private func send(_ request: URLRequest, authorized: Bool, allowRetry: Bool = true) async throws -> Data {
        var request = request
        if authorized, let token = TokenStore.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, httpResponse) = try await perform(request)

        if httpResponse.statusCode == 401, authorized, allowRetry {
            try await refreshTokensIfNeeded()
            return try await send(request, authorized: authorized, allowRetry: false)
        }

        guard !(200...299).contains(httpResponse.statusCode) else { return data }
        let body = try? decoder.decode(ServerErrorBody.self, from: data)
        announceAppWideRejection(code: body?.code, message: body?.readableMessage, data: data)
        if httpResponse.statusCode >= 500 { throw APIError.unavailable(status: httpResponse.statusCode) }
        let message = body?.readableMessage ?? "Ошибка сервера (\(httpResponse.statusCode))"
        guard let code = body?.code else { throw APIError.server(message) }
        throw APIError.rejected(code: code, message: message)
    }

    /// Обслуживание и блокировка касаются всего приложения, а не экрана, который сделал запрос: о них узнаёт AppStatus.
    /// Сам запрос при этом завершается ошибкой как обычно (при обслуживании — временной: экран покажет сохранённое).
    private nonisolated func announceAppWideRejection(code: String?, message: String?, data: Data) {
        switch code {
        case ServerErrorCode.maintenance:
            NotificationCenter.default.post(name: .maintenanceDetected, object: message)
        case ServerErrorCode.accountBanned:
            guard let notice = try? ISO8601Coding.makeDecoder().decode(BanNotice.self, from: data) else { return }
            NotificationCenter.default.post(name: .accountBanned, object: notice)
        default:
            break
        }
    }

    /// path может содержать query — appendingPathComponent её экранировал бы, поэтому собираем через URLComponents.
    private func makeURL(path: String) -> URL {
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent(parts[0]), resolvingAgainstBaseURL: false)!
        if parts.count > 1 {
            components.percentEncodedQuery = parts[1]
        }
        return components.url!
    }

    func refreshTokensIfNeeded() async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }

        let task = Task<Void, Error> {
            guard let refreshToken = TokenStore.shared.refreshToken else {
                expireSession()
                throw APIError.unauthorized
            }

            var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("/auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(["refreshToken": refreshToken])

            let (data, httpResponse) = try await perform(request)

            switch httpResponse.statusCode {
            case 200:
                let tokens = try decoder.decode(AuthTokens.self, from: data)
                TokenStore.shared.save(tokens: tokens)
            case 401, 403:
                // Refresh-токен отозван или просрочен — сессия действительно закончилась.
                expireSession()
                throw APIError.unauthorized
            case 500...:
                // Сбой сервера не значит, что сессия умерла: токены не трогаем, пусть вызывающий повторит позже.
                throw APIError.unavailable(status: httpResponse.statusCode)
            default:
                throw APIError.server("Ошибка сервера (\(httpResponse.statusCode))")
            }
        }

        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    /// Сетевые ошибки URLSession приводим к APIError.offline — по нему экраны и очередь отправки отличают
    /// «нет связи» (показать сохранённое, повторить) от отказа сервера.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.connectivityErrors.contains(error.code) {
            throw APIError.offline
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, httpResponse)
    }

    private static let connectivityErrors: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
    ]

    /// Очищает токены и сообщает UI (AuthViewModel), что нужно вернуться на экран входа.
    private nonisolated func expireSession() {
        TokenStore.shared.clear()
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }
}

private struct ServerErrorBody: Decodable {
    let message: StringOrArray?
    let error: String?
    /// Есть только у отказов, на которые клиент реагирует по-разному (см. ServerErrorCode).
    let code: String?

    var readableMessage: String? {
        message?.value ?? error
    }
}

/// NestJS class-validator иногда отдаёт `message` строкой, иногда массивом строк — разбираем оба варианта.
private enum StringOrArray: Decodable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
        } else {
            self = .multiple(try container.decode([String].self))
        }
    }

    var value: String {
        switch self {
        case .single(let value): return value
        case .multiple(let values): return values.joined(separator: ", ")
        }
    }
}

struct EmptyResponse: Decodable {}

struct ChatSummary: Decodable {
    let id: String
    let type: ChatType
    let title: String?
    let username: String?
}

/// Изменение приватности: nil-поля не отправляются и на сервере не меняются.
struct PrivacyUpdate: Encodable {
    var messagePrivacy: PrivacyLevel?
    var groupInvitePrivacy: PrivacyLevel?
    var messengerSearchByUsername: Bool?
    var datingSearchByUsername: Bool?
}

/// Поля зашифрованного сообщения секретного чата — уходят вместо текста.
/// nil-поля JSONEncoder не пишет — сервер получает только заданные.
private struct SendMessageBody: Encodable {
    let text: String
    let attachmentId: String?
    let ciphertext: String?
    let senderKey: String?
    let viewTimerSec: Int?
    let replyToId: String?
    let clientMessageId: String
}

private struct ForwardMessagesBody: Encodable {
    let messageIds: [String]
}

private struct ClearHistoryBody: Encodable {
    let forEveryone: Bool
}

struct TimedPhotoOpening: Decodable {
    let openedAt: Date
    let expiresAt: Date
}

struct EncryptedPayload {
    let ciphertext: String
    let senderKey: String
}

private struct E2EKeyResponse: Decodable {
    let publicKey: String
}

private struct BotTokenResponse: Decodable {
    let token: String
}

private struct IceServersResponse: Decodable {
    let iceServers: [IceServer]
}

private struct CreateChannelRequest: Encodable {
    let title: String
    let username: String
}
