import Foundation
import Combine

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Сколько запросов на переписку и первых сообщений ждут моего ответа — счётчик строки «Запросы».
    @Published private(set) var incomingRequestsCount = 0
    /// Незнакомому напрямую не написать: для него экран списка открывает запрос на переписку.
    @Published var requestTarget: User?

    private var cancellables = Set<AnyCancellable>()
    private var isRefreshing = false
    private var hasPendingRefresh = false

    init() {
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
                    self?.applyIncoming(message: message)
                }
            }
            .store(in: &cancellables)

        // Пока сети или сокета не было (приложение в фоне), новые сообщения и чаты прошли мимо — перечитываем список.
        NotificationCenter.default.publisher(for: .networkBecameAvailable)
            .merge(with: NotificationCenter.default.publisher(for: .realtimeReconnected))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refreshChats() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Список с прошлого раза виден сразу; без сети fetchChats вернёт его же.
        if chats.isEmpty, let cached = await APIClient.shared.cachedChats() {
            chats = cached
        }
        do {
            chats = try await APIClient.shared.fetchChats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startChat(with user: User, secret: Bool = false) async -> Chat? {
        do {
            let summary = secret
                ? try await APIClient.shared.createSecretChat(userId: user.id)
                : try await APIClient.shared.createChat(userId: user.id)
            if let existing = chats.first(where: { $0.id == summary.id }) {
                return existing
            }
            let chat = Chat(id: summary.id, type: summary.type, title: summary.title, username: nil, myRole: .member, participants: [user], lastMessage: nil)
            chats.insert(chat, at: 0)
            return chat
        } catch let error as APIError where error.code == ServerErrorCode.chatRequestRequired {
            requestTarget = user
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createChannel(title: String, username: String) async -> Chat? {
        do {
            let summary = try await APIClient.shared.createChannel(title: title, username: username)
            let chat = Chat(id: summary.id, type: summary.type, title: summary.title, username: summary.username, myRole: .admin, participants: [], lastMessage: nil)
            chats.insert(chat, at: 0)
            return chat
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func joinChannel(_ channel: PublicChannel) async -> Chat? {
        do {
            try await APIClient.shared.subscribeToChannel(chatId: channel.id)
            let chat = Chat(id: channel.id, type: .channel, title: channel.title, username: channel.username, myRole: .member, participants: [], lastMessage: nil)
            chats.insert(chat, at: 0)
            return chat
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func removeChat(id: String) {
        chats.removeAll { $0.id == id }
    }

    func setPinned(_ chat: Chat, pinned: Bool) async {
        do {
            if pinned {
                try await APIClient.shared.pinChat(chatId: chat.id)
            } else {
                try await APIClient.shared.unpinChat(chatId: chat.id)
            }
            // Событие chat.pinned придёт следом с серверным временем; до него ставим своё, чтобы строка сразу переехала.
            applyPinned(chatId: chat.id, pinnedAt: pinned ? (chat.pinnedAt ?? Date()) : nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearHistory(_ chat: Chat, forEveryone: Bool) async {
        do {
            try await APIClient.shared.clearHistory(chatId: chat.id, forEveryone: forEveryone)
            applyCleared(chatId: chat.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ chat: Chat) async {
        do {
            try await APIClient.shared.deleteChat(chatId: chat.id)
            removeChat(id: chat.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPinned(chatId: String, pinnedAt: Date?) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].pinnedAt = pinnedAt
        chats = chats.sortedForList()
    }

    private func applyCleared(chatId: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].lastMessage = nil
    }

    /// Чат, который только что открылся ответом на запрос или парой: его ещё может не быть в списке.
    func chat(withId id: String) async -> Chat? {
        if let chat = chats.first(where: { $0.id == id }) { return chat }
        await refreshChats()
        return chats.first { $0.id == id }
    }

    func loadRequestsCount() async {
        // Счётчик второстепенный: без сети остаётся прежним, а список чатов из-за него ошибкой не мигает.
        guard let inbox = try? await APIClient.shared.fetchChatRequests() else { return }
        incomingRequestsCount = inbox.incoming.count
    }

    /// Событий может прийти пачкой (например, несколько сообщений подряд из нового чата) — держим один запрос
    /// в полёте, а события, пришедшие во время него, склеиваем в один повторный.
    private func refreshChats() async {
        if isRefreshing {
            hasPendingRefresh = true
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            hasPendingRefresh = false
            do {
                chats = try await APIClient.shared.fetchChats()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } while hasPendingRefresh
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .newMessage(let message):
            applyIncoming(message: message)

        case .messageUpdated(let message):
            guard let index = chats.firstIndex(where: { $0.lastMessage?.id == message.id }) else { return }
            chats[index].lastMessage = message

        case .messageDeleted(let chatId, let messageId):
            // Какое сообщение стало последним, знает только сервер.
            guard chats.contains(where: { $0.id == chatId && $0.lastMessage?.id == messageId }) else { return }
            Task { await refreshChats() }

        case .chatPinned(let chatId, let pinnedAt):
            applyPinned(chatId: chatId, pinnedAt: pinnedAt)

        case .chatMuted(let chatId, let mutedUntil):
            guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
            chats[index].mutedUntil = mutedUntil

        case .chatCleared(let chatId):
            applyCleared(chatId: chatId)

        case .chatDeleted(let chatId):
            removeChat(id: chatId)

        case .datingUnmatched:
            // Чат пары стал закрытым (вкладка «Удалённые») — какой именно и до какого числа хранится, знает сервер.
            Task { await refreshChats() }

        case .chatRequestsChanged:
            // На мой запрос ответили — появился новый чат; пришёл новый запрос — вырос счётчик.
            Task {
                await refreshChats()
                await loadRequestsCount()
            }

        case .datingIntro:
            Task { await loadRequestsCount() }

        case .presence(let userId, let presence):
            for index in chats.indices where chats[index].peer?.id == userId {
                chats[index].participants[0].presence = presence
            }

        case .receipt(let chatId, _, let kind, let at):
            // Свои квитанции сервер нам не шлёт — только отметки собеседников.
            guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
            chats[index].deliveredAt = max(chats[index].deliveredAt ?? at, at)
            if kind == .read {
                chats[index].readAt = max(chats[index].readAt ?? at, at)
            }

        default:
            break
        }
    }

    private func applyIncoming(message: Message) {
        guard let index = chats.firstIndex(where: { $0.id == message.chatId }) else {
            // Чата нет в списке: новый собеседник, приглашение в группу/канал или сообщение до первого load().
            Task { await refreshChats() }
            return
        }
        // Подтверждение своего могло прийти позже более свежего входящего — старым превью не затираем.
        if let current = chats[index].lastMessage, current.createdAt > message.createdAt { return }
        chats[index].lastMessage = message
        // Закреплённые остаются сверху — новое сообщение поднимает чат только среди незакреплённых.
        chats = chats.sortedForList()
    }
}
