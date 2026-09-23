import SwiftUI

/// Переписка с тем, с кем чата ещё нет: выглядит как чат, но первое сообщение уходит запросом. Сервер сам решает как:
/// видимой анкете нужного пола — первым сообщением знакомств (лайк, лимит в сутки), остальным — обычным запросом.
/// Настоящий чат откроется, когда ответят; если человек уже лайкнул в ответ, — сразу.
struct PendingChatView: View {
    let user: User
    let onChatOpened: (String) -> Void

    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Уже отправленное и ждущее ответа — второй запрос тому же человеку сервер не примет.
    @State private var sent: (text: String, isIntro: Bool)?
    @State private var showCard = false

    private let maxLength = 500

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Label("Вы ещё не переписывались. Первое сообщение уйдёт запросом — чат откроется, когда ответят. Без ссылок, телефонов и контактов в других мессенджерах.", systemImage: "envelope.badge")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .appCard(cornerRadius: 18, padding: 14)
                if let sent {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(sent.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(.brandFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(sent.isIntro ? "Ждёт ответа — ответит, и вы станете парой" : "Ждёт ответа")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .safeAreaInset(edge: .bottom) {
            if sent == nil { composer }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showCard = true } label: {
                    HStack(spacing: 8) {
                        AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 30)
                        Text(user.displayName).font(.app(.headline)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Открыть анкету")
            }
        }
        .sheet(isPresented: $showCard) {
            NavigationStack { PersonCardView(user: user) }
        }
        .task { await loadSentRequest() }
        .alert("Не отправлено", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.brandFill, in: Circle())
            }
            .disabled(isSending || trimmed.isEmpty || trimmed.count > maxLength)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Запрос уже отправлен раньше — показываем его, а не пустое поле, которое сервер всё равно отклонит.
    private func loadSentRequest() async {
        guard let inbox = try? await APIClient.shared.fetchChatRequests(),
              let request = inbox.sent.first(where: { $0.recipientId == user.id }) else { return }
        sent = (request.text, request.kind == .intro)
    }

    private func send() {
        isSending = true
        let message = trimmed
        Task {
            defer { isSending = false }
            do {
                let result = try await APIClient.shared.sendChatRequest(userId: user.id, text: message)
                if let chatId = result.match?.chatId {
                    onChatOpened(chatId)
                } else {
                    sent = (message, result.kind == .intro)
                    text = ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Карточка человека из поиска или из личного чата: его анкета, если она видна, иначе — имя и @username.
struct PersonCardView: View {
    let user: User
    /// Из поиска — «Написать» внизу. Из чата кнопки нет: переписка уже открыта.
    var onMessage: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var profile: DatingProfilePublic?
    @State private var catalog: DatingCatalog?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let profile {
                DatingProfileDetailView(profile: profile, catalog: catalog, onMessage: onMessage)
            } else {
                basicCard
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task { await load() }
    }

    private var basicCard: some View {
        VStack(spacing: 12) {
            AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 104)
            HStack(spacing: 4) {
                Text(user.displayName).font(.display(.title2))
                if user.isBot == true { BotBadge() }
            }
            Text("@\(user.username)").foregroundStyle(.secondary)
            Text(loadError ?? "Анкета скрыта или ещё не прошла проверку")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            if let onMessage {
                Button(action: onMessage) {
                    Label("Написать", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.appPrimary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }

    private func load() async {
        defer { isLoading = false }
        guard user.isBot != true else { return }
        catalog = try? await APIClient.shared.fetchDatingCatalog()
        do {
            profile = try await APIClient.shared.fetchDatingProfile(userId: user.id)
        } catch let error as APIError where error.isTransient {
            loadError = error.localizedDescription
        } catch {
            // 404 — анкеты нет или она не видна: показываем имя и @username, этого хватает, чтобы написать.
            profile = nil
        }
    }
}

/// Общий ящик «Запросы»: первые сообщения знакомств и запросы на переписку. Ответ открывает личный чат.
struct ChatRequestsView: View {
    let onOpenChat: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inbox: ChatRequestInbox?
    @State private var opened: IncomingChatRequest?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let inbox {
                Section(inbox.incoming.isEmpty ? "Вам написали" : "Вам написали · \(inbox.incoming.count)") {
                    ForEach(inbox.incoming) { request in
                        Button { opened = request } label: {
                            RequestRow(name: request.from.displayName, avatarUrl: request.from.avatarUrl, photoId: request.from.profile?.photoIds.first, text: request.text, isIntro: request.kind == .intro)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !inbox.sent.isEmpty {
                    Section {
                        ForEach(inbox.sent) { request in
                            RequestRow(name: request.recipientName, avatarUrl: request.avatarUrl, photoId: request.photoId, text: request.text, isIntro: request.kind == .intro)
                        }
                    } header: {
                        Text("Вы написали")
                    } footer: {
                        Text("Чат откроется, когда вам ответят.")
                    }
                }
            }
        }
        .appScreenBackground()
        .overlay {
            if inbox == nil && errorMessage == nil {
                ProgressView()
            } else if let inbox, inbox.incoming.isEmpty && inbox.sent.isEmpty {
                ContentUnavailableView("Запросов нет", systemImage: "tray", description: Text("Здесь появятся сообщения от тех, с кем вы ещё не переписывались"))
            } else if let errorMessage, inbox == nil {
                ContentUnavailableView("Не загрузилось", systemImage: "wifi.slash", description: Text(errorMessage))
            }
        }
        .navigationTitle("Запросы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $opened) { request in
            NavigationStack {
                IncomingRequestView(request: request) { chatId in
                    opened = nil
                    if let chatId {
                        onOpenChat(chatId)
                    } else {
                        Task { await load() }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            inbox = try await APIClient.shared.fetchChatRequests()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RequestRow: View {
    let name: String
    let avatarUrl: String?
    let photoId: String?
    let text: String
    let isIntro: Bool

    var body: some View {
        HStack(spacing: 12) {
            if avatarUrl == nil, let photoId {
                DatingPhotoView(attachmentId: photoId, cornerRadius: 26)
                    .frame(width: 52, height: 52)
            } else {
                AvatarView(avatarUrl: avatarUrl, name: name, size: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.app(.body, weight: .semibold)).lineLimit(1)
                    if isIntro {
                        Label("знакомство", systemImage: "heart.fill")
                            .font(.app(.caption2, weight: .semibold))
                            .foregroundStyle(Color.champagne)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.champagneSoft, in: Capsule())
                    }
                }
                Text(text).font(.app(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

/// Входящий запрос: кто пишет, что написал, ответ или отказ. Об отказе отправителю не сообщается.
private struct IncomingRequestView: View {
    let request: IncomingChatRequest
    /// chatId открывшегося чата; nil — запрос отклонён (или пара возникла, но её чат уже удалён).
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reply = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var catalog: DatingCatalog?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AvatarView(avatarUrl: request.from.avatarUrl, name: request.from.displayName, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.from.displayName).font(.app(.headline))
                        if let username = request.from.username {
                            Text("@\(username)").font(.app(.subheadline)).foregroundStyle(.secondary)
                        }
                        Text(request.kind == .intro ? "Ответите — и вы станете парой" : "Ответите — и откроется чат")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                if let profile = request.from.profile {
                    NavigationLink("Анкета") {
                        DatingProfileDetailView(profile: profile, catalog: catalog)
                    }
                }
            }
            Section("Сообщение") {
                Text(request.text)
            }
            Section("Ваш ответ") {
                TextField("Ответ", text: $reply, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section {
                Button("Ответить", action: send)
                    .font(.app(.body, weight: .semibold))
                    .disabled(isBusy || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Отклонить", role: .destructive, action: decline)
                    .disabled(isBusy)
            }
        }
        .appScreenBackground()
        .navigationTitle(request.kind == .intro ? "Первое сообщение" : "Запрос на переписку")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task { catalog = try? await APIClient.shared.fetchDatingCatalog() }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func send() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                onDone(try await APIClient.shared.replyToChatRequest(request, text: text))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decline() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await APIClient.shared.declineChatRequest(request)
                onDone(nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
