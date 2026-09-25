import Combine
import CryptoKit
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Своё сообщение сохранено через REST (очередь отправки, пересылка) — события от сервера на это не будет.
    /// object — [Message]. Слушают список чатов (превью) и экран чата (замена временного пузыря).
    static let ownMessagesSentViaREST = Notification.Name("com.orzuapp.messenger.ownMessagesSentViaREST")
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var errorMessage: String?
    /// Секретный чат: ключ собеседника сменился с прошлого раза — отправка заблокирована, пока пользователь не подтвердит.
    @Published private(set) var peerKeyChanged = false
    /// Код для сверки ключей с собеседником (см. SecretChatCrypto.safetyNumber).
    @Published private(set) var safetyNumber: String?
    /// Отметки собеседников — из них считаются галочки своих сообщений (Message.deliveryStatus).
    @Published private(set) var deliveredAt: Date?
    @Published private(set) var readAt: Date?
    /// Ждут в очереди отправки (MessageOutbox): id временный, действия с ними недоступны.
    @Published private(set) var pendingIds: Set<String> = []
    /// Сообщение, на которое отвечают из поля ввода; nil — обычная отправка.
    @Published var replyTo: Message?
    /// Закреплённое сообщение чата — видно всем участникам.
    @Published private(set) var pinnedMessage: Message?
    /// Текущая ступень «Пути к браку», если это чат пары знакомств и путь не завершён.
    @Published private(set) var pairStageName: String?
    /// «В сети» собеседника в личном и секретном чате.
    @Published private(set) var peerPresence: Presence?
    /// Кто сейчас набирает сообщение (id участников); отметка гаснет сама через `typingVisibleFor`.
    @Published private(set) var typingUserIds: Set<String> = []
    /// Показан фрагмент переписки вокруг найденного сообщения, а не последние сообщения.
    @Published private(set) var isShowingHistorySlice = false
    /// Чат удалил собеседник (или вы на другом устройстве) — экран нужно закрыть.
    @Published private(set) var wasDeleted = false
    /// Без звука до этой даты; nil — звук включён. Прошедшая дата — тоже включён, см. isMuted.
    @Published private(set) var mutedUntil: Date?

    var isMuted: Bool {
        mutedUntil.map { $0 > Date() } ?? false
    }

    // Совпадает с лимитом backend — проверяем заранее, чтобы не гнать 20+ МБ ради ошибки 413.
    static let maxAttachmentBytes = 20 * 1024 * 1024
    private static let maxPhotoDimension: CGFloat = 2048
    /// Сервер пересылает «печатает» не чаще раза в 2 с (TYPING_THROTTLE_MS) — чаще слать незачем.
    private static let typingSendInterval: TimeInterval = 2
    /// Если новых «печатает» не приходит, отметка гаснет: человек перестал набирать или ушёл из чата.
    private static let typingVisibleFor: Duration = .seconds(5)
    /// Совпадает с MIN_SEARCH_LENGTH на backend.
    static let minSearchLength = 2
    /// Совпадает с MAX_FORWARD_BATCH на backend: больше за один запрос сервер не перешлёт.
    static let maxForwardBatch = 10

    /// Меняется, только когда пару удаляют при открытом чате: он становится закрытым, только для чтения.
    @Published private(set) var chat: Chat
    let currentUserId: String
    private var cancellables = Set<AnyCancellable>()
    private let participantsById: [String: User]
    private var peerPublicKey: Curve25519.KeyAgreement.PublicKey?
    private var peerKeyBase64: String?
    /// Последнее входящее, о прочтении которого уже сообщили серверу, — чтобы не слать одно и то же повторно.
    private var lastMarkedReadId: String?
    private var lastTypingSentAt: Date?
    private var typingExpiryTasks: [String: Task<Void, Never>] = [:]

    var isSecret: Bool { chat.type == .secret }

    init(chat: Chat, currentUserId: String) {
        self.chat = chat
        self.currentUserId = currentUserId
        self.participantsById = Dictionary(uniqueKeysWithValues: chat.participants.map { ($0.id, $0) })
        self.deliveredAt = chat.deliveredAt
        self.readAt = chat.readAt
        self.peerPresence = chat.peer?.presence
        self.mutedUntil = chat.mutedUntil

        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ownMessagesSentViaREST)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                for message in notification.object as? [Message] ?? [] {
                    self?.confirmQueued(message)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .outgoingMessageFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let failure = notification.object as? OutgoingMessageFailure else { return }
                self?.dropQueued(failure)
            }
            .store(in: &cancellables)

        // Пока сети или сокета не было (приложение в фоне), новые сообщения прошли мимо — догружаем последние.
        NotificationCenter.default.publisher(for: .networkBecameAvailable)
            .merge(with: NotificationCenter.default.publisher(for: .realtimeReconnected))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isShowingHistorySlice else { return }
                Task { await self.loadHistory() }
            }
            .store(in: &cancellables)
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isSecret { try await preparePeerKey() }
            // Переписка с прошлого раза видна сразу; без сети fetchMessages вернёт её же.
            if messages.isEmpty, let cached = await APIClient.shared.cachedMessages(chatId: chat.id) {
                showLatest(cached)
            }
            showLatest(try await APIClient.shared.fetchMessages(chatId: chat.id))
            markReadIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadPinnedMessage()
    }

    /// Последняя страница истории и под ней — ещё не отправленное из очереди (кроме того, что сервер уже принял).
    private func showLatest(_ page: [Message]) {
        let acceptedIds = Set(page.compactMap(\.clientMessageId))
        let queued = MessageOutbox.shared.items(chatId: chat.id).filter { !acceptedIds.contains($0.id) }
        messages = page.map(decrypted) + queued.map { decrypted($0.message(senderId: currentUserId)) }
        pendingIds = Set(queued.map(\.id))
        isShowingHistorySlice = false
    }

    /// Закреплённое сообщение есть только в GET /chats/:id. Не загрузилось — чат работает и без плашки.
    private func loadPinnedMessage() async {
        do {
            let detail = try await APIClient.shared.fetchChatDetail(chatId: chat.id)
            pinnedMessage = detail.pinnedMessage.map(decrypted)
            chat.closedAt = detail.closedAt
            chat.deletesAt = detail.deletesAt
            if let matchId = detail.matchId { await loadPairStage(matchId: matchId) }
        } catch let error as APIError where error.isTransient {
            // Без сети плашка просто не появится — ошибку про это уже видно по баннеру «Нет сети».
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Плашка пары только подсказывает, где вы на пути: не загрузилась — чат работает без неё, ошибку не показываем.
    private func loadPairStage(matchId: String) async {
        guard let journey = try? await APIClient.shared.fetchJourney(matchId: matchId),
              journey.endedAt == nil,
              let catalog = try? await APIClient.shared.fetchDatingCatalog() else { return }
        pairStageName = catalog.stage(journey.stage)?.name
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chat.canPost else { return }
        deliver(text: trimmed, attachment: nil)
    }

    /// Вызывается на каждое изменение черновика; на сервер уходит не чаще раза в `typingSendInterval`.
    func draftChanged(_ draft: String) {
        guard chat.type != .channel, !draft.isEmpty else { return }
        let now = Date()
        if let lastTypingSentAt, now.timeIntervalSince(lastTypingSentAt) < Self.typingSendInterval { return }
        lastTypingSentAt = now
        WebSocketClient.shared.sendTyping(chatId: chat.id)
    }

    /// Имя для цитаты, пометки «переслано» и строки «печатает».
    func displayName(of userId: String) -> String {
        if userId == currentUserId { return "Вы" }
        return participantsById[userId]?.displayName ?? "Участник"
    }

    /// Подпись под названием чата: «печатает…» важнее, чем «в сети».
    var headerStatus: String? {
        if let typingId = typingUserIds.first {
            return chat.type == .group ? "\(displayName(of: typingId)) печатает…" : "печатает…"
        }
        return peerPresence?.subtitle()
    }

    // MARK: - Действия с сообщением

    func isMine(_ message: Message) -> Bool {
        message.senderId == currentUserId
    }

    /// Из секретного чата и фото с таймером сервер не пересылает — их смысл в том, чтобы не оставлять копий.
    func canForward(_ message: Message) -> Bool {
        !isSecret && message.viewTimerSec == nil && !pendingIds.contains(message.id)
    }

    /// В канале закрепляют только админы — те же, кто может писать (так же проверяет сервер).
    func canPin(_ message: Message) -> Bool {
        chat.canPost && !pendingIds.contains(message.id)
    }

    /// Пожаловаться можно на чужое сообщение в личном чате или группе; в канале автор всегда админ канала.
    func canReport(_ message: Message) -> Bool {
        !isMine(message) && !pendingIds.contains(message.id) && chat.type != .channel
    }

    func canEdit(_ message: Message) -> Bool {
        isMine(message) && !pendingIds.contains(message.id) && chat.canPost && !peerKeyChanged
    }

    /// «Удалить у всех» — только своё (так же проверяет сервер).
    func canDeleteForEveryone(_ message: Message) -> Bool {
        isMine(message) && !pendingIds.contains(message.id)
    }

    func status(of message: Message) -> DeliveryStatus? {
        // В канале квитанций нет (см. backend ReceiptsService).
        guard isMine(message), chat.type != .channel else { return nil }
        return message.deliveryStatus(isPending: pendingIds.contains(message.id), deliveredAt: deliveredAt, readAt: readAt)
    }

    func edit(_ message: Message, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit(message), trimmed != message.text, !trimmed.isEmpty || message.attachment != nil else { return }
        do {
            let encrypted = isSecret ? try encrypt(trimmed) : nil
            let updated = try await APIClient.shared.editMessage(
                chatId: chat.id, messageId: message.id, text: isSecret ? "" : trimmed, encrypted: encrypted
            )
            upsert(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Убираем сразу, не дожидаясь сервера; если он откажет — возвращаем на место.
    func delete(_ message: Message, forEveryone: Bool) async {
        guard !pendingIds.contains(message.id), let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages.remove(at: index)
        do {
            try await APIClient.shared.deleteMessage(chatId: chat.id, messageId: message.id, forEveryone: forEveryone)
        } catch {
            messages.insert(message, at: min(index, messages.count))
            errorMessage = error.localizedDescription
        }
    }

    /// Повторное нажатие на свою реакцию снимает её, другая — заменяет.
    func toggleReaction(_ emoji: String, on message: Message) async {
        guard !pendingIds.contains(message.id) else { return }
        let newEmoji = message.myReaction(currentUserId: currentUserId) == emoji ? nil : emoji
        do {
            upsert(try await APIClient.shared.setReaction(chatId: chat.id, messageId: message.id, emoji: newEmoji))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Пересылка в выбранный чат одним запросом — сервер сохранит исходный порядок сообщений.
    /// true — получилось (экран выбора можно закрыть).
    func forward(_ selected: [Message], toChatId: String) async -> Bool {
        let ids = selected.filter(canForward).map(\.id)
        guard !ids.isEmpty, ids.count <= Self.maxForwardBatch else {
            errorMessage = "Переслать можно от 1 до \(Self.maxForwardBatch) сообщений за раз"
            return false
        }
        do {
            let forwarded = try await APIClient.shared.forwardMessages(toChatId: toChatId, messageIds: ids)
            NotificationCenter.default.post(name: .ownMessagesSentViaREST, object: forwarded)
            // Переслали в этот же чат — сообщение придёт не событием (сервер не шлёт message.new отправителю), а ответом.
            if toChatId == chat.id {
                for message in forwarded where !messages.contains(where: { $0.id == message.id }) {
                    messages.append(decrypted(message))
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// message = nil — открепить. Плашку меняет событие chat.pinnedMessage, оно приходит и самому закрепившему.
    func pin(_ message: Message?) async {
        do {
            try await APIClient.shared.pinMessage(chatId: chat.id, messageId: message?.id)
            pinnedMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// option = nil — включить звук. Список чатов узнает об изменении из события chat.muted.
    func setMute(_ option: MuteOption?) async {
        do {
            if let option {
                mutedUntil = try await APIClient.shared.muteChat(chatId: chat.id, duration: option.duration)
            } else {
                try await APIClient.shared.unmuteChat(chatId: chat.id)
                mutedUntil = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Очистить у всех можно только личный и секретный чат, и не чат удалённой пары — его хранят ради жалоб.
    var canClearForEveryone: Bool {
        chat.canDelete && !chat.isClosed
    }

    func clearHistory(forEveryone: Bool) async {
        do {
            try await APIClient.shared.clearHistory(chatId: chat.id, forEveryone: forEveryone)
            applyCleared()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteChat() async -> Bool {
        do {
            try await APIClient.shared.deleteChat(chatId: chat.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// В секретном чате сервер хранит только шифротекст — искать ему не по чему.
    var canSearch: Bool {
        !isSecret
    }

    func search(_ query: String) async -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch, trimmed.count >= Self.minSearchLength else { return [] }
        do {
            return try await APIClient.shared.searchMessages(chatId: chat.id, query: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Показать найденное сообщение. Если оно за пределами загруженных, берём страницу истории, которая им заканчивается:
    /// сервер отдаёт сообщения строго раньше курсора, поэтому курсор — на миллисекунду позже найденного.
    /// Возвращает, удалось ли сообщение показать.
    func reveal(_ message: Message) async -> Bool {
        if messages.contains(where: { $0.id == message.id }) { return true }
        do {
            let page = try await APIClient.shared.fetchMessages(chatId: chat.id, before: message.createdAt.addingTimeInterval(0.001))
            messages = page.map(decrypted)
            isShowingHistorySlice = true
            return messages.contains { $0.id == message.id }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func blockPeer() async {
        guard let peer = chat.participants.first else { return }
        do {
            try await APIClient.shared.blockUser(id: peer.id)
            errorMessage = "\(peer.displayName) заблокирован"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Пользователь сверил код безопасности (или доверяет собеседнику) и принимает его новый ключ.
    func acceptChangedPeerKey() async {
        guard let peerKeyBase64, let peer = chat.participants.first else { return }
        E2EKeyStore.shared.pin(peerKey: peerKeyBase64, userId: peer.id)
        peerKeyChanged = false
        await loadHistory()
    }

    /// Фото с таймером — только людям лично: в канале его увидели бы все подписчики (так же проверяет сервер).
    var canSendTimedPhoto: Bool {
        chat.type == .direct || chat.type == .group
    }

    func sendAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        mediaKind: AttachmentKind? = nil,
        durationSec: Int? = nil,
        viewTimerSec: Int? = nil
    ) async {
        // Файлы лежат на сервере в открытом виде — в секретный чат их не пускаем.
        guard chat.canPost, !isSecret else { return }
        guard data.count <= Self.maxAttachmentBytes else {
            errorMessage = "Файл больше 20 МБ"
            return
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let attachment = try await APIClient.shared.uploadAttachment(
                data: data, fileName: fileName, mimeType: mimeType, mediaKind: mediaKind, durationSec: durationSec
            )
            deliver(text: "", attachment: attachment, viewTimerSec: viewTimerSec)
        } catch let error as APIError where error.isTransient {
            // Нет связи — файл ждёт в очереди и загрузится вместе с отправкой, когда сеть появится.
            let upload = PendingUpload(fileName: fileName, mimeType: mimeType, mediaKind: mediaKind, durationSec: durationSec)
            deliver(text: "", attachment: nil, viewTimerSec: viewTimerSec, upload: (upload, data))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendPhoto(_ item: PhotosPickerItem, viewTimerSec: Int? = nil) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            errorMessage = "Не удалось прочитать фото"
            return
        }
        // Пересжимаем в JPEG: фото из библиотеки часто HEIC на десятки МБ, а в чате хватает 2048 px.
        guard let jpeg = image.downscaled(maxDimension: Self.maxPhotoDimension).jpegData(compressionQuality: 0.8) else {
            errorMessage = "Не удалось подготовить фото"
            return
        }
        await sendAttachment(data: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg", viewTimerSec: viewTimerSec)
    }

    /// Запись голосового или «кружка» во временном файле: после загрузки (или ошибки) файл больше не нужен.
    func sendRecording(_ recording: MediaRecording) async {
        defer { try? FileManager.default.removeItem(at: recording.fileURL) }
        do {
            let data = try Data(contentsOf: recording.fileURL)
            await sendAttachment(
                data: data,
                fileName: recording.fileURL.lastPathComponent,
                mimeType: recording.mimeType,
                mediaKind: recording.kind,
                durationSec: recording.durationSec
            )
        } catch {
            errorMessage = "Не удалось прочитать запись: \(error.localizedDescription)"
        }
    }

    func timedPhotoState(of message: Message) -> TimedPhotoState? {
        message.timedPhotoState(currentUserId: currentUserId, now: Date())
    }

    /// Запускает таймер на сервере. Отметку ставим и локально — не ждём message.updated, чтобы пузырь сразу стал «открытым».
    func openTimedPhoto(_ message: Message) async -> TimedPhotoOpening? {
        do {
            let opening = try await APIClient.shared.openTimedPhoto(chatId: chat.id, messageId: message.id)
            if let index = messages.firstIndex(where: { $0.id == message.id }),
               messages[index].views?.contains(where: { $0.userId == currentUserId }) != true {
                messages[index].views = (messages[index].views ?? []) + [MessageView(userId: currentUserId, openedAt: opening.openedAt)]
            }
            return opening
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func sendFile(at url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maxAttachmentBytes else {
                errorMessage = "Файл больше 20 МБ"
                return
            }
            let data = try Data(contentsOf: url)
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            await sendAttachment(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
        } catch {
            errorMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }

    func previewURL(for attachment: Attachment) async -> URL? {
        do {
            return try await AttachmentLoader.shared.temporaryFileURL(for: attachment)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Сообщение сразу появляется в чате и уходит в очередь: она отправит его сейчас или когда появится сеть.
    private func deliver(text: String, attachment: Attachment?, viewTimerSec: Int? = nil, upload: (PendingUpload, Data)? = nil) {
        var encrypted: EncryptedPayload?
        if isSecret {
            do {
                encrypted = try encrypt(text)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        // В секретном чате текст уходит только внутри шифротекста; локально показываем исходный.
        let wireText = isSecret ? "" : text

        let item = OutgoingMessage(
            id: UUID().uuidString, chatId: chat.id, createdAt: Date(), text: wireText,
            ciphertext: encrypted?.ciphertext, senderKey: encrypted?.senderKey, viewTimerSec: viewTimerSec,
            replyToId: replyTo?.id, replyPreview: replyTo.map(replyPreview), attachment: attachment, upload: upload?.0
        )
        var bubble = item.message(senderId: currentUserId)
        if upload == nil { bubble.text = text }
        pendingIds.insert(item.id)
        messages.append(bubble)
        replyTo = nil
        MessageOutbox.shared.enqueue(item, uploadData: upload?.1)
        // Своё сообщение отправлено — дальше показываем свежие, а не найденный фрагмент.
        if isShowingHistorySlice { Task { await loadHistory() } }
    }

    /// Цитата для своего ещё не подтверждённого сообщения — сервер пришлёт настоящую в ответе.
    private func replyPreview(of message: Message) -> ReplyPreview {
        ReplyPreview(
            id: message.id,
            senderId: message.senderId,
            text: message.text,
            attachment: message.attachment.map { ReplyPreview.ReplyAttachment(kind: $0.kind) }
        )
    }

    /// Очередь отправила сообщение — меняем временный пузырь на настоящий.
    private func confirmQueued(_ message: Message) {
        guard message.chatId == chat.id, let clientMessageId = message.clientMessageId, pendingIds.contains(clientMessageId) else { return }
        replace(tempId: clientMessageId, with: message)
    }

    private func dropQueued(_ failure: OutgoingMessageFailure) {
        guard failure.chatId == chat.id, pendingIds.contains(failure.id) else { return }
        messages.removeAll { $0.id == failure.id }
        pendingIds.remove(failure.id)
        errorMessage = "Сообщение не отправлено: \(failure.reason)"
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .newMessage(let message):
            guard message.chatId == chat.id, !messages.contains(where: { $0.id == message.id }) else { return }
            // Сообщение пришло — значит, автор уже не печатает.
            stopTyping(userId: message.senderId)
            // Во фрагменте старой переписки новое сообщение встало бы не на своё место.
            guard !isShowingHistorySlice else { return }
            messages.append(decrypted(message))
            markReadIfNeeded()

        case .typing(let chatId, let userId):
            guard chatId == chat.id, userId != currentUserId else { return }
            startTyping(userId: userId)

        case .presence(let userId, let presence):
            guard userId == chat.peer?.id else { return }
            peerPresence = presence
            if !presence.online { stopTyping(userId: userId) }

        case .chatMuted(let chatId, let mutedUntil):
            guard chatId == chat.id else { return }
            self.mutedUntil = mutedUntil

        case .chatPinnedMessage(let chatId, let messageId):
            guard chatId == chat.id else { return }
            if messageId == nil {
                pinnedMessage = nil
            } else if let loaded = messages.first(where: { $0.id == messageId }) {
                pinnedMessage = loaded
            } else {
                Task { await loadPinnedMessage() }
            }

        case .chatCleared(let chatId):
            guard chatId == chat.id else { return }
            applyCleared()

        case .chatDeleted(let chatId):
            guard chatId == chat.id else { return }
            wasDeleted = true

        case .datingUnmatched(_, let chatId):
            // Пару удалили, пока чат открыт: сервер закрыл его только для чтения — перечитываем, до какого числа он хранится.
            guard chatId == chat.id else { return }
            pairStageName = nil
            Task { await loadPinnedMessage() }

        case .messageUpdated(let message):
            guard message.chatId == chat.id, messages.contains(where: { $0.id == message.id }) else { return }
            upsert(message)

        case .messageDeleted(let chatId, let messageId):
            guard chatId == chat.id else { return }
            messages.removeAll { $0.id == messageId }
            // Сервер обнуляет цитату и закрепление удалённого сообщения — повторяем это у себя.
            for index in messages.indices where messages[index].replyTo?.id == messageId {
                messages[index].replyTo = nil
            }
            if pinnedMessage?.id == messageId { pinnedMessage = nil }
            if replyTo?.id == messageId { replyTo = nil }

        case .receipt(let chatId, _, let kind, let at):
            // Свои квитанции сервер нам не шлёт — только отметки собеседников.
            guard chatId == chat.id else { return }
            // Отметки только растут; в группе галочки ставит самый быстрый из участников.
            switch kind {
            case .delivered: deliveredAt = max(deliveredAt ?? at, at)
            case .read:
                readAt = max(readAt ?? at, at)
                deliveredAt = max(deliveredAt ?? at, at)
            }

        case .error(let text):
            errorMessage = text

        default:
            break // события звонков этот экран не касаются — их слушает CallManager
        }
    }

    private func replace(tempId: String, with message: Message) {
        pendingIds.remove(tempId)
        guard let index = messages.firstIndex(where: { $0.id == tempId }) else { return }
        messages[index] = decrypted(message)
    }

    private func upsert(_ message: Message) {
        if pinnedMessage?.id == message.id { pinnedMessage = decrypted(message) }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = decrypted(message)
    }

    /// Неподтверждённые сообщения оставляем: сервер ещё пришлёт на них ответ, и они окажутся уже после очистки.
    private func applyCleared() {
        messages.removeAll { !pendingIds.contains($0.id) }
        pinnedMessage = nil
        replyTo = nil
        isShowingHistorySlice = false
    }

    private func startTyping(userId: String) {
        typingUserIds.insert(userId)
        typingExpiryTasks[userId]?.cancel()
        typingExpiryTasks[userId] = Task { [weak self] in
            try? await Task.sleep(for: Self.typingVisibleFor)
            guard !Task.isCancelled else { return }
            self?.stopTyping(userId: userId)
        }
    }

    private func stopTyping(userId: String) {
        typingExpiryTasks.removeValue(forKey: userId)?.cancel()
        typingUserIds.remove(userId)
    }

    /// Экран чата открыт — значит, последнее входящее прочитано. В канале квитанций нет.
    private func markReadIfNeeded() {
        guard
            chat.type != .channel,
            let last = messages.last(where: { !isMine($0) }),
            last.id != lastMarkedReadId
        else { return }
        lastMarkedReadId = last.id
        Task {
            do {
                try await APIClient.shared.markRead(chatId: chat.id, messageId: last.id)
            } catch {
                // Не критично для пользователя: сбросим отметку, и следующее сообщение или открытие чата повторит попытку.
                if lastMarkedReadId == last.id { lastMarkedReadId = nil }
            }
        }
    }

    // MARK: - Секретный чат

    private func preparePeerKey() async throws {
        guard let peer = chat.participants.first else { throw SecretChatCrypto.CryptoError.invalidKey }
        let keyBase64 = try await APIClient.shared.fetchE2EKey(userId: peer.id)
        let publicKey = try SecretChatCrypto.publicKey(base64: keyBase64)
        peerPublicKey = publicKey
        peerKeyBase64 = keyBase64

        switch E2EKeyStore.shared.status(ofPeerKey: keyBase64, userId: peer.id) {
        case .firstSeen: E2EKeyStore.shared.pin(peerKey: keyBase64, userId: peer.id)
        case .unchanged: break
        case .changed: peerKeyChanged = true
        }

        let myKey = try E2EKeyStore.shared.privateKey(for: currentUserId)
        safetyNumber = SecretChatCrypto.safetyNumber(myKey.publicKey.rawRepresentation, publicKey.rawRepresentation)
    }

    private func encrypt(_ text: String) throws -> EncryptedPayload {
        guard let peerPublicKey, !peerKeyChanged else {
            throw SecretChatCrypto.CryptoError.invalidKey
        }
        let myKey = try E2EKeyStore.shared.privateKey(for: currentUserId)
        let ciphertext = try SecretChatCrypto.seal(text, privateKey: myKey, peerPublicKey: peerPublicKey, chatId: chat.id, senderId: currentUserId)
        return EncryptedPayload(ciphertext: ciphertext, senderKey: myKey.publicKey.rawRepresentation.base64EncodedString())
    }

    /// Возвращает копию сообщения с расшифрованным текстом (или пометкой, если расшифровать нельзя).
    private func decrypted(_ message: Message) -> Message {
        var copy = message
        if let ciphertext = message.ciphertext {
            copy.text = decryptedText(ciphertext, senderId: message.senderId, senderKey: message.senderKey)
        }
        // Цитата в секретном чате зашифрована так же, как само сообщение, — ключом её автора.
        if let reply = message.replyTo, let ciphertext = reply.ciphertext {
            copy.replyTo?.text = decryptedText(ciphertext, senderId: reply.senderId, senderKey: reply.senderKey)
        }
        return copy
    }

    private func decryptedText(_ ciphertext: String, senderId: String, senderKey: String?) -> String {
        (try? decryptText(ciphertext, senderId: senderId, senderKey: senderKey)) ?? "⚠️ Не удалось расшифровать сообщение"
    }

    private func decryptText(_ ciphertext: String, senderId: String, senderKey: String?) throws -> String {
        guard let peerPublicKey, let peerKeyBase64 else { throw SecretChatCrypto.CryptoError.invalidKey }
        // Входящее, зашифрованное не подтверждённым нами ключом, не показываем как настоящее: его мог подделать сервер.
        if senderId != currentUserId, senderKey != peerKeyBase64 || peerKeyChanged {
            throw SecretChatCrypto.CryptoError.invalidKey
        }
        let myKey = try E2EKeyStore.shared.privateKey(for: currentUserId)
        return try SecretChatCrypto.open(ciphertext, privateKey: myKey, peerPublicKey: peerPublicKey, chatId: chat.id, senderId: senderId)
    }

    /// Имя отправителя показывается только в группах — в личном чате и так понятно, кто пишет.
    func senderName(for message: Message) -> String? {
        guard chat.type == .group, message.senderId != currentUserId else { return nil }
        return participantsById[message.senderId]?.displayName
    }
}

/// Сроки из меню «Без звука».
enum MuteOption: CaseIterable, Identifiable {
    case hour
    case eightHours
    case week
    case forever

    var id: Self { self }

    var title: String {
        switch self {
        case .hour: return "На 1 час"
        case .eightHours: return "На 8 часов"
        case .week: return "На неделю"
        case .forever: return "Навсегда"
        }
    }

    /// nil — без срока.
    var duration: TimeInterval? {
        switch self {
        case .hour: return 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .forever: return nil
        }
    }
}

extension Date {
    /// Сервер хранит «навсегда» как 9999 год — всё дальше века считаем бессрочным.
    var isEffectivelyForever: Bool {
        timeIntervalSinceNow > 100 * 365 * 24 * 60 * 60
    }
}
