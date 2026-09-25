import Foundation

enum ChatType: String, Codable, Hashable {
    case direct = "DIRECT"
    case group = "GROUP"
    case channel = "CHANNEL"
    /// Сквозное шифрование 1:1: текст видят только два устройства, сервер хранит шифротекст.
    case secret = "SECRET"
}

struct Chat: Codable, Identifiable, Hashable {
    let id: String
    let type: ChatType
    let title: String?
    let username: String?
    let myRole: ParticipantRole
    /// Чат закреплён вверху списка (не больше MAX_PINNED_CHATS = 5 на backend). nil — не закреплён.
    var pinnedAt: Date? = nil
    /// Без звука до этой даты: push о сообщениях чата не приходят. Истёкшее сервер не отдаёт.
    var mutedUntil: Date? = nil

    /// Сохранённый список мог пролежать дольше срока — истёкшее отключение уже не считается.
    var isMuted: Bool {
        mutedUntil.map { $0 > Date() } ?? false
    }
    var participants: [User]
    var lastMessage: Message?
    /// Самые поздние отметки «доставлено» и «прочитано» среди собеседников — для галочек у своих сообщений.
    var deliveredAt: Date?
    var readAt: Date?
    /// Чат удалённой пары: закрыт только для чтения (ради жалоб) и удалится насовсем в deletesAt.
    var closedAt: Date?
    var deletesAt: Date?

    var isClosed: Bool { closedAt != nil }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return participants.first?.displayName ?? "Чат"
    }

    /// Собеседник в личном и секретном чате; в группе и канале его нет.
    var peer: User? {
        type == .direct || type == .secret ? participants.first : nil
    }

    /// Из группы и канала выходят, а не удаляют их (так же проверяет сервер).
    var canDelete: Bool {
        type == .direct || type == .secret
    }

    /// В канале писать может только владелец/соадмин — остальные только читают. В чат удалённой пары не пишет никто.
    var canPost: Bool {
        !isClosed && (type != .channel || myRole == .admin)
    }

    /// Звонить можно собеседнику 1:1 и в группу (mesh до 4 участников — см. CallManager).
    var canCall: Bool {
        guard !isClosed else { return false }
        switch type {
        case .direct, .secret: return participants.first?.isBot != true
        case .group: return true
        case .channel: return false
        }
    }
}

extension Array where Element == Chat {
    /// Порядок как на сервере (ChatsService.listForUser): закреплённые сверху, последний закреплённый первым,
    /// остальные — по времени последнего сообщения.
    func sortedForList() -> [Chat] {
        sorted { a, b in
            if a.pinnedAt != nil || b.pinnedAt != nil {
                return (a.pinnedAt ?? .distantPast) > (b.pinnedAt ?? .distantPast)
            }
            return (a.lastMessage?.createdAt ?? .distantPast) > (b.lastMessage?.createdAt ?? .distantPast)
        }
    }
}
