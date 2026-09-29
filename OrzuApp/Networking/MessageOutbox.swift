import Foundation
import UIKit
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
    /// Заявка на загрузку уже получена, файл уходит в фоновой сессии: после перезапуска дожидаемся её, а не шлём заново.
    var uploadId: String?

    /// Пока файла нет на сервере, пузырь показывает подпись вместо превью.
    var placeholder: String {
        switch mediaKind {
        case .voice: return String(localized: "🎤 Голосовое сообщение")
        case .videoNote: return String(localized: "📹 Видеосообщение")
        case .video: return String(localized: "🎬 Видео")
        case .image: return String(localized: "📷 Фото")
        case .file, nil: return mimeType.hasPrefix("image/") ? String(localized: "📷 Фото") : "📎 \(fileName)"
        }
    }
}

/// Откуда очередь берёт файл: фото уже в памяти, запись и документ лежат на диске и в память не читаются.
enum UploadSource {
    case data(Data)
    case file(URL)
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
    var recipientKeyId: String?
    var viewTimerSec: Int?
    var replyToId: String?
    var replyPreview: ReplyPreview?
    var attachment: Attachment?
    var upload: PendingUpload?

    /// Пузырь в чате до ответа сервера.
    func message(senderId: String) -> Message {
        Message(
            id: id, chatId: chatId, senderId: senderId, text: upload?.placeholder ?? text, createdAt: createdAt,
            attachment: attachment, ciphertext: ciphertext, senderKey: senderKey, recipientKeyId: recipientKeyId, viewTimerSec: viewTimerSec,
            replyTo: replyPreview, clientMessageId: id
        )
    }
}

/// Пауза перед повтором, растущая вдвое после каждой неудачи: base, 2·base, 4·base… но не больше maxDelay.
/// Случайный разброс ±20% нужен, чтобы после сбоя сервера клиенты не возвращались к нему все в одну секунду.
struct RetryBackoff {
    let base: TimeInterval
    let maxDelay: TimeInterval
    private(set) var attempt = 0

    init(base: TimeInterval, maxDelay: TimeInterval) {
        self.base = base
        self.maxDelay = maxDelay
    }

    /// Пауза без разброса перед попыткой номер attempt (считая с нуля).
    static func delay(attempt: Int, base: TimeInterval, maxDelay: TimeInterval) -> TimeInterval {
        let exponent = Double(min(max(attempt, 0), 30))
        return min(base * pow(2, exponent), maxDelay)
    }

    mutating func next() -> Duration {
        let delay = Self.delay(attempt: attempt, base: base, maxDelay: maxDelay)
        attempt += 1
        return .milliseconds(Int(delay * Double.random(in: 0.8...1.2) * 1000))
    }

    mutating func reset() {
        attempt = 0
    }
}

/// Очередь исходящих сообщений. Переживает перезапуск приложения и отправляет всё по порядку, как только
/// появится связь. Повтор безопасен: сервер узнаёт уже сохранённое сообщение по clientMessageId.
@MainActor
final class MessageOutbox {
    static let shared = MessageOutbox()

    private static let queueKey = "queue"

    private(set) var items: [OutgoingMessage] = []

    private let store = DiskStore(name: "Outbox", base: .applicationSupportDirectory)
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Outbox")
    private var isSending = false
    private var retryTask: Task<Void, Never>?
    /// Сервер недоступен при живой сети — не долбим его, но и не ждём смены сети, которой может не быть:
    /// 15 с, 30 с, 1 мин… до 5 мин между попытками. Первое же принятое сообщение сбрасывает паузу.
    private var retryBackoff = RetryBackoff(base: 15, maxDelay: 300)
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

    func enqueue(_ item: OutgoingMessage) {
        items.append(item)
        saveQueue()
        flush()
    }

    /// Сообщение с файлом, которого ещё нет на сервере (item.upload != nil): файл хранится в очереди до отправки.
    func enqueue(_ item: OutgoingMessage, upload source: UploadSource) throws {
        switch source {
        case .data(let data): store.save(data, for: Self.fileKey(item.id))
        case .file(let url): try store.copyFile(at: url, for: Self.fileKey(item.id))
        }
        enqueue(item)
    }

    func flush() {
        Task { await sendPending() }
    }

    /// Досылает очередь и ждёт окончания — фоновому обновлению iOS даёт на это ограниченное время.
    func sendPending() async {
        guard !isSending, !items.isEmpty, TokenStore.shared.accessToken != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        // Отдельная задача: отмена фонового обновления по таймауту оборвала бы запросы, и сообщения ушли бы в отказ.
        await Task { await sendAll() }.value
    }

    /// Выход из аккаунта: неотправленное не должно уйти от имени следующего пользователя.
    func removeAll() {
        retryTask?.cancel()
        retryTask = nil
        items = []
        retryBackoff.reset()
        store.removeAll()
    }

    private func sendAll() async {
        isSending = true
        // Приложение свернули посреди отправки или его разбудила фоновая загрузка — просим у iOS время дослать.
        let backgroundTime = BackgroundTime(name: "Outbox")
        defer {
            isSending = false
            backgroundTime.end()
        }

        while let item = items.first {
            do {
                let message = try await send(item)
                retryBackoff.reset()
                remove(id: item.id)
                NotificationCenter.default.post(name: .ownMessagesSentViaREST, object: [message])
            } catch let error as APIError where error.isTransient {
                scheduleRetry()
                return
            } catch APIError.rateLimited(let retryAfter, _, _) {
                // Лимит отправки — не отказ по существу: сообщение ждёт столько, сколько попросил сервер.
                scheduleRetry(notBefore: retryAfter)
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
        if var upload = item.upload {
            guard let fileURL = store.existingFileURL(for: Self.fileKey(item.id)) else {
                throw APIError.server(String(localized: "Файл для отправки больше недоступен"))
            }
            var isUploaded = false
            if let uploadId = upload.uploadId {
                isUploaded = try await APIClient.shared.resumeUpload(id: uploadId)
            }
            if !isUploaded {
                let ticket = try await APIClient.shared.createUpload(
                    for: fileURL, fileName: upload.fileName, mimeType: upload.mimeType, mediaKind: upload.mediaKind
                )
                // Запоминаем до PUT: если приложение выгрузят посреди загрузки, после перезапуска найдём её по этому id.
                upload.uploadId = ticket.uploadId
                item.upload = upload
                replace(item)
                try await APIClient.shared.putUpload(ticket, fileURL: fileURL, mimeType: upload.mimeType)
            }
            guard let uploadId = upload.uploadId else { throw APIError.invalidResponse }
            item.attachment = try await APIClient.shared.completeUpload(id: uploadId)
            item.upload = nil
            // Файл уже на сервере: при повторе после сбоя загружать его второй раз не нужно.
            replace(item)
            store.remove(Self.fileKey(item.id))
        }
        let encrypted = item.ciphertext.flatMap { ciphertext in
            item.senderKey.map { EncryptedPayload(ciphertext: ciphertext, senderKey: $0, recipientKeyId: item.recipientKeyId) }
        }
        return try await APIClient.shared.sendMessage(
            chatId: item.chatId, text: item.text, attachmentId: item.attachment?.id, encrypted: encrypted,
            viewTimerSec: item.viewTimerSec, replyToId: item.replyToId, clientMessageId: item.id
        )
    }

    private func scheduleRetry(notBefore minimumDelay: TimeInterval = 0) {
        let delay = max(retryBackoff.next(), .milliseconds(Int(minimumDelay * 1000)))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
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

/// Фоновое время iOS на дела, начатые до сворачивания. Когда оно кончается, отпускаем его сами — иначе система
/// завершит приложение; фоновая загрузка при этом продолжится без нас.
@MainActor
private final class BackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
