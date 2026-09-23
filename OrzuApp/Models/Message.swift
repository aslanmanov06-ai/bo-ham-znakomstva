import Foundation

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let chatId: String
    let senderId: String
    var text: String
    let createdAt: Date
    var attachment: Attachment? = nil
    /// Только в секретных чатах: ChaChaPoly-конверт и публичный ключ отправителя (см. SecretChatCrypto).
    var ciphertext: String? = nil
    var senderKey: String? = nil
    var editedAt: Date? = nil
    var reactions: [MessageReaction]? = nil
    /// Фото с таймером: получатель видит его столько секунд после открытия.
    var viewTimerSec: Int? = nil
    /// Кто и когда открыл фото с таймером.
    var views: [MessageView]? = nil
    /// Сообщение, на которое отвечают. Сервер обнуляет связь, если оригинал удалили.
    var replyTo: ReplyPreview? = nil
    /// Пересланное: автор оригинала и его имя на момент пересылки. Автора могли удалить — тогда остаётся только имя.
    var forwardedFromId: String? = nil
    var forwardedFromName: String? = nil
    /// Id, который клиент дал сообщению при отправке: по нему своё сообщение из очереди узнаётся в ответе сервера.
    var clientMessageId: String? = nil

    /// Совпадает с VIEW_TIMER_OPTIONS на backend.
    static let viewTimerOptions = [10, 15, 30, 60]

    var previewText: String {
        if !text.isEmpty { return text }
        if ciphertext != nil { return "🔒 Зашифрованное сообщение" }
        switch attachment?.kind {
        case .image: return viewTimerSec == nil ? "Фото" : "Фото с таймером"
        case .file: return "Файл: \(attachment?.fileName ?? "")"
        case .voice: return "Голосовое сообщение"
        case .videoNote: return "Видеосообщение"
        case .video: return "Видео"
        case nil: return ""
        }
    }

    /// nil — обычное сообщение. Сервер сам не отдаст файл получателю до открытия и после таймера.
    func timedPhotoState(currentUserId: String, now: Date) -> TimedPhotoState? {
        guard let viewTimerSec, attachment?.kind == .image else { return nil }
        if senderId == currentUserId {
            return .own(viewed: !(views ?? []).isEmpty)
        }
        guard let view = views?.first(where: { $0.userId == currentUserId }) else { return .unopened }
        let expiresAt = view.openedAt.addingTimeInterval(TimeInterval(viewTimerSec))
        return now < expiresAt ? .open(expiresAt: expiresAt) : .expired
    }

    /// Реакции, сгруппированные по эмодзи в порядке набора `MessageReaction.allowed`.
    func reactionSummary(currentUserId: String) -> [ReactionSummary] {
        let all = reactions ?? []
        return MessageReaction.allowed.compactMap { emoji in
            let matching = all.filter { $0.emoji == emoji }
            guard !matching.isEmpty else { return nil }
            return ReactionSummary(emoji: emoji, count: matching.count, isMine: matching.contains { $0.userId == currentUserId })
        }
    }

    func myReaction(currentUserId: String) -> String? {
        reactions?.first { $0.userId == currentUserId }?.emoji
    }

    /// Галочки у своего сообщения. deliveredAt/readAt — самые поздние отметки собеседников (см. GET /chats).
    func deliveryStatus(isPending: Bool, deliveredAt: Date?, readAt: Date?) -> DeliveryStatus {
        if isPending { return .sending }
        if let readAt, readAt >= createdAt { return .read }
        if let deliveredAt, deliveredAt >= createdAt { return .delivered }
        return .sent
    }
}

/// Цитата над сообщением-ответом: сервер отдаёт оригинал укороченным (см. messagePublicInclude на backend).
struct ReplyPreview: Codable, Hashable {
    let id: String
    let senderId: String
    var text: String
    /// В секретном чате текст цитаты тоже зашифрован — расшифровывает ChatViewModel.
    var ciphertext: String? = nil
    var senderKey: String? = nil
    var attachment: ReplyAttachment? = nil

    /// У цитаты известен только вид вложения — ни имени файла, ни размера сервер в неё не кладёт.
    struct ReplyAttachment: Codable, Hashable {
        let kind: AttachmentKind
    }

    var previewText: String {
        if !text.isEmpty { return text }
        if ciphertext != nil { return "🔒 Зашифрованное сообщение" }
        switch attachment?.kind {
        case .image: return "Фото"
        case .file: return "Файл"
        case .voice: return "Голосовое сообщение"
        case .videoNote: return "Видеосообщение"
        case .video: return "Видео"
        case nil: return ""
        }
    }
}

struct MessageReaction: Codable, Hashable {
    let userId: String
    let emoji: String

    /// Совпадает с ALLOWED_REACTIONS на backend — другие эмодзи сервер отклонит.
    static let allowed = ["👍", "❤️", "😂", "😮", "😢", "🔥", "👎", "🙏"]
}

struct MessageView: Codable, Hashable {
    let userId: String
    let openedAt: Date
}

enum TimedPhotoState: Equatable {
    /// Своё фото видно без таймера; viewed — кто-то из получателей его уже открыл.
    case own(viewed: Bool)
    case unopened
    /// Открыто, таймер ещё идёт (например, просмотр прервали сворачиванием приложения).
    case open(expiresAt: Date)
    case expired
}

struct ReactionSummary: Hashable {
    let emoji: String
    let count: Int
    let isMine: Bool
}

enum DeliveryStatus: Equatable {
    /// Ещё не подтверждено сервером.
    case sending
    /// Сервер сохранил, но до устройства собеседника пока не дошло.
    case sent
    case delivered
    case read
}
