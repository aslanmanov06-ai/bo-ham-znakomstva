import Foundation

enum ParticipantRole: String, Codable, Hashable {
    case admin = "ADMIN"
    case member = "MEMBER"
}

struct ChatMember: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    var isBot: Bool? = nil
    let role: ParticipantRole
    /// Только у собеседника по личному чату — в группах и каналах сервер присутствие не отдаёт.
    var presence: Presence? = nil
}

struct ChatDetail: Decodable {
    let id: String
    let type: ChatType
    let title: String?
    let participants: [ChatMember]
    /// Закреплённое сообщение чата — одно на всех. Есть только в GET /chats/:id, в списке чатов его нет.
    var pinnedMessage: Message? = nil
    /// Личный чат пары знакомств — по нему показываем ступень «Пути к браку».
    var matchId: String? = nil
    /// Пару удалили: чат только для чтения до deletesAt.
    var closedAt: Date? = nil
    var deletesAt: Date? = nil
}
