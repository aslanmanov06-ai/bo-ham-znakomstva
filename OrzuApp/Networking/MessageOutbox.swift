import Foundation
import os

extension Notification.Name {
    /// Сервер отказался принять сообщение из очереди (чат удалён, нет прав и т.п.). object — OutgoingMessageFailure.
    static let outgoingMessageFailed = Notification.Name("com.orzuapp.messenger.outgoingMessageFailed")
}

struct OutgoingMessageFailure {
    let id: String
    let chatId: String
    let reason: String
}

/// Файл, который не успели загрузить на сервер: сами байты лежат рядом, в хранилище очереди.
struct PendingUpload: Codable, Hashable {
    let fileName: String
    let mimeType: String
    var mediaKind: AttachmentKind?
    var durationSec: Int?

    /// Пока файла нет на сервере, пузырь показывает подпись вместо превью.
    var placeholder: String {
        switch mediaKind {
        case .voice: return "🎤 Голосовое сообщение"
        case .videoNote: return "📹 Видеосообщение"
        case .video: return "🎬 Видео"
        case .image: return "📷 Фото"
        case .file, nil: return mimeType.hasPrefix("image/") ? "📷 Фото" : "📎 \(fileName)"
        }
    }
}

/// Сообщение, которое ещё не принял сервер. id — он же clientMessageId и временный id пузыря в чате.
struct OutgoingMessage: Codable, Identifiable, Hashable {
    let id: String
    let chatId: String
    let createdAt: Date
    /// То, что уходит на сервер: в секретном чате text пустой, а содержимое — в ciphertext.
    let text: String
    var ciphertext: String?
    var senderKey: String?
    var viewTimerSec: Int?
    var replyToId: String?
    var replyPreview: ReplyPreview?
    var attachment: Attachment?
    var upload: PendingUpload?

    /// Пузырь в чате до ответа сервера.
    func message(senderId: String) -> Message {
        Message(
            id: id, chatId: chatId, senderId: senderId, text: upload?.placeholder ?? text, createdAt: createdAt,
            attachment: attachment, ciphertext: ciphertext, senderKey: senderKey, viewTimerSec: viewTimerSec,
            replyTo: replyPreview, clientMessageId: id
        )
    }
}

/// Очередь исходящих сообщений. Переживает перезапуск приложения и отправляет всё по порядку, как только
/// появится связь. Повтор безопасен: сервер узнаёт уже сохранённое сообщение по clientMessageId.
@MainActor
final class MessageOutbox {
    static let shared = MessageOutbox()

    /// Сервер недоступен при живой сети — не долбим его, но и не ждём смены сети, которой может не быть.
    private static let retryDelay: Duration = .seconds(15)
    private static let queueKey = "queue"

    private(set) var items: [OutgoingMessage] = []

    private let store = DiskStore(name: "Outbox", base: .applicationSupportDirectory)
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Outbox")
    private var isSending = false
    private var retryTask: Task<Void, Never>?
    private var networkObserver: NSObjectProtocol?

    private init() {
        items = loadQueue()
        networkObserver = NotificationCenter.default.addObserver(forName: .networkBecameAvailable, object: nil, queue: .main) { _ in
            Task { @MainActor in MessageOutbox.shared.flush() }
        }
    }

    func items(chatId: String) -> [OutgoingMessage] {
        items.filter { $0.chatId == chatId }
    }

    /// uploadData — байты файла, если его ещё не загрузили на сервер (item.upload != nil).
    func enqueue(_ item: OutgoingMessage, uploadData: Data? = nil) {
        if let uploadData { store.save(uploadData, for: Self.fileKey(item.id)) }
        items.append(item)
        saveQueue()
        flush()
    }

    func flush() {
        guard !isSending, !items.isEmpty, TokenStore.shared.accessToken != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        Task { await sendAll() }
    }

    /// Выход из аккаунта: неотправленное не должно уйти от имени следующего пользователя.
    func removeAll() {
        retryTask?.cancel()
        retryTask = nil
        items = []
        store.removeAll()
    }

    private func sendAll() async {
        isSending = true
        defer { isSending = false }

        while let item = items.first {
            do {
                let message = try await send(item)
                remove(id: item.id)
                NotificationCenter.default.post(name: .ownMessagesSentViaREST, object: [message])
            } catch let error as APIError where error.isTransient {
                scheduleRetry()
                return
            } catch APIError.unauthorized {
                // Сессия закончилась: AuthViewModel выведет на экран входа и очистит очередь.
                return
            } catch {
                // Повтор не поможет — сервер отказал по существу. Убираем, иначе очередь встанет навсегда.
                logger.error("Сообщение из очереди отклонено: \(error.localizedDescription, privacy: .public)")
                remove(id: item.id)
                let failure = OutgoingMessageFailure(id: item.id, chatId: item.chatId, reason: error.localizedDescription)
                NotificationCenter.default.post(name: .outgoingMessageFailed, object: failure)
            }
        }
    }

    private func send(_ item: OutgoingMessage) async throws -> Message {
        var item = item
        if let upload = item.upload {
            guard let data = store.load(Self.fileKey(item.id)) else {
                throw APIError.server("Файл для отправки больше недоступен")
            }
            item.attachment = try await APIClient.shared.uploadAttachment(
                data: data, fileName: upload.fileName, mimeType: upload.mimeType, mediaKind: upload.mediaKind, durationSec: upload.durationSec
            )
            item.upload = nil
            // Файл уже на сервере: при повторе после сбоя загружать его второй раз не нужно.
            replace(item)
            store.remove(Self.fileKey(item.id))
        }
        let encrypted = item.ciphertext.flatMap { ciphertext in
            item.senderKey.map { EncryptedPayload(ciphertext: ciphertext, senderKey: $0) }
        }
        return try await APIClient.shared.sendMessage(
            chatId: item.chatId, text: item.text, attachmentId: item.attachment?.id, encrypted: encrypted,
            viewTimerSec: item.viewTimerSec, replyToId: item.replyToId, clientMessageId: item.id
        )
    }

    private func scheduleRetry() {
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func replace(_ item: OutgoingMessage) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        saveQueue()
    }

    private func remove(id: String) {
        items.removeAll { $0.id == id }
        store.remove(Self.fileKey(id))
        saveQueue()
    }

    private func loadQueue() -> [OutgoingMessage] {
        guard let data = store.load(Self.queueKey) else { return [] }
        do {
            return try ISO8601Coding.makeDecoder().decode([OutgoingMessage].self, from: data)
        } catch {
            logger.error("Очередь сообщений не прочиталась и сброшена: \(error.localizedDescription, privacy: .public)")
            store.removeAll()
            return []
        }
    }

    private func saveQueue() {
        do {
            store.save(try ISO8601Coding.makeEncoder().encode(items), for: Self.queueKey)
        } catch {
            logger.error("Не удалось сохранить очередь сообщений: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func fileKey(_ id: String) -> String {
        "file-\(id)"
    }
}
