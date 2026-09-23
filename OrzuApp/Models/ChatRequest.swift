import Foundation

/// Человек на другой стороне запроса: имя, @username, аватар и анкета, если она есть.
struct ChatRequestPerson: Decodable, Hashable {
    let userId: String
    let username: String?
    let displayName: String
    let avatarUrl: String?
    let profile: DatingProfilePublic?
}

/// Входящий запрос из общего ящика «Запросы»: первое сообщение знакомств (intro) или обычный запрос на переписку.
struct IncomingChatRequest: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable, Hashable {
        case intro
        case request
    }

    let kind: Kind
    let id: String
    let text: String
    let createdAt: Date
    /// Только у первых сообщений: через сутки без ответа они истекают.
    let expiresAt: Date?
    let from: ChatRequestPerson

    private enum CodingKeys: String, CodingKey {
        case kind, id, text, createdAt, expiresAt, from
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        switch kind {
        case .request:
            from = try container.decode(ChatRequestPerson.self, forKey: .from)
        case .intro:
            // У первого сообщения отправитель — сразу анкета.
            let profile = try container.decode(DatingProfilePublic.self, forKey: .from)
            from = ChatRequestPerson(
                userId: profile.userId,
                username: profile.username,
                displayName: profile.displayName,
                avatarUrl: nil,
                profile: profile
            )
        }
    }
}

/// Отправленный запрос, ещё без ответа. Отклонённый выглядит так же: об отказе сервер не сообщает.
struct SentChatRequest: Decodable, Identifiable, Hashable {
    let kind: IncomingChatRequest.Kind
    let id: String
    let text: String
    let createdAt: Date
    let expiresAt: Date?
    let recipientId: String
    let recipientName: String
    let avatarUrl: String?
    /// Главное фото анкеты — у первых сообщений сервер отдаёт его вместо аватара.
    let photoId: String?

    private enum CodingKeys: String, CodingKey {
        case kind, id, text, createdAt, expiresAt, to
    }

    private struct IntroRecipientBody: Decodable {
        let userId: String
        let displayName: String
        let photoId: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(IncomingChatRequest.Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        switch kind {
        case .request:
            let person = try container.decode(ChatRequestPerson.self, forKey: .to)
            recipientId = person.userId
            recipientName = person.displayName
            avatarUrl = person.avatarUrl
            photoId = nil
        case .intro:
            let recipient = try container.decode(IntroRecipientBody.self, forKey: .to)
            recipientId = recipient.userId
            recipientName = recipient.displayName
            avatarUrl = nil
            photoId = recipient.photoId
        }
    }
}

struct ChatRequestInbox: Decodable {
    let incoming: [IncomingChatRequest]
    let sent: [SentChatRequest]
}

/// Ответ POST /chat-requests: ушло первым сообщением знакомств (может сразу стать парой) или обычным запросом.
struct SendChatRequestResult: Decodable {
    let kind: IncomingChatRequest.Kind
    /// Только у первого сообщения: получатель уже лайкнул в ответ — сообщение сразу ушло в чат новой пары.
    let match: DatingMatch?
}

struct ChatRequestReply: Decodable {
    let chatId: String
}
