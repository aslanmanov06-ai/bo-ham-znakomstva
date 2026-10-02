import SwiftUI

private enum ActiveSheet: Identifiable, Hashable {
    case newChat
    /// Анкета найденного человека с кнопкой «Написать».
    case person(User)
    case requests

    var id: Self { self }
}

/// Вся переписка в одном месте: новые пары, первые сообщения и запросы, обычные чаты.
struct ChatListView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    /// Модели живут на уровне вкладок: по ним считается число на вкладке «Чаты».
    @ObservedObject var viewModel: ChatListViewModel
    @ObservedObject var matches: MatchesViewModel
    @ObservedObject var dating: DatingViewModel
    @ObservedObject private var drafts = ChatDraftStore.shared
    @ObservedObject private var push = PushManager.shared
    @State private var activeSheet: ActiveSheet?
    @State private var openedChat: Chat?
    @State private var query = ""
    @State private var chatPendingDeletion: Chat?
    /// Люди с сервера по запросу из поиска — как «Глобальный поиск» в Telegram.
    @State private var foundUsers: [User] = []
    @State private var userSearchError: String?
    @State private var isSearchingUsers = false
    /// Переписка с тем, с кем чата ещё нет: первое сообщение уйдёт запросом.
    @State private var pendingPerson: User?
    /// Вкладка «Удалённые»: чаты удалённых пар, только для чтения, отдельно от обычных.
    @State private var showDeleted = false
    /// Пара, открытая из шапки её чата: «Путь к браку», встречи, удаление пары.
    @State private var openedPair: DatingMatch?

    // body разбит на части: одним выражением компилятор не успевал вывести типы
    // («unable to type-check this expression in reasonable time»).
    var body: some View {
        NavigationStack {
            chatList
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { activeSheet = .newChat } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Новый чат")
                    }
                }
                .task {
                    await viewModel.load()
                    await viewModel.loadRequestsCount()
                }
                .task(id: dating.stage) {
                    guard dating.stage == .ready else { return }
                    await matches.load()
                }
                // Незнакомому сервер не дал открыть чат — открываем переписку, где первое сообщение уйдёт запросом.
                .onChange(of: viewModel.requestTarget) { _, user in
                    guard let user else { return }
                    viewModel.requestTarget = nil
                    pendingPerson = user
                }
                // «Написать» из анкеты во вкладке знакомств.
                // Запрос — отдельной задачей: обнуление pending меняет id, и SwiftUI отменяет этот .task —
                // запрос обрывался с URLError.cancelled и показывал «Ошибка: Cancelled».
                .task(id: push.pendingConversation?.id) {
                    guard let user = push.pendingConversation else { return }
                    push.pendingConversation = nil
                    Task { openedChat = await viewModel.startChat(with: user) }
                }
                .task(id: push.pendingChatId) {
                    guard let chatId = push.pendingChatId else { return }
                    push.pendingChatId = nil
                    Task {
                        if !viewModel.chats.contains(where: { $0.id == chatId }) {
                            await viewModel.load()
                        }
                        openedChat = viewModel.chats.first { $0.id == chatId }
                    }
                }
                .refreshable {
                    await viewModel.load()
                    await viewModel.loadRequestsCount()
                    if dating.stage == .ready { await matches.load() }
                }
                .sheet(item: $activeSheet) { sheet in
                    sheetContent(for: sheet)
                }
                .navigationDestination(item: $pendingPerson) { user in
                    PendingChatView(user: user) { chatId in
                        pendingPerson = nil
                        Task { openedChat = await viewModel.chat(withId: chatId) }
                    }
                }
                .onChange(of: openedChat?.id) { _, chatId in
                    viewModel.activeChatId = chatId
                }
                .navigationDestination(item: $openedChat) { chat in
                    if let currentUserId = authViewModel.currentUser?.id {
                        ChatView(
                            viewModel: ChatViewModel(chat: chat, currentUserId: currentUserId),
                            onOpenPair: pair(forChatId: chat.id).map { match in { openedPair = match } }
                        ) {
                            openedChat = nil
                            viewModel.removeChat(id: chat.id)
                        }
                    }
                }
                .navigationDestination(item: $openedPair) { match in
                    MatchDetailView(match: match, dating: dating, matches: matches)
                        .alert("Ошибка", isPresented: Binding(get: { matches.errorMessage != nil }, set: { if !$0 { matches.errorMessage = nil } })) {
                            Button("Ок") { matches.errorMessage = nil }
                        } message: {
                            Text(matches.errorMessage ?? "")
                        }
                }
        }
    }

    private var chatList: some View {
        List {
            listContent
        }
        .listStyle(.plain)
        .appScreenBackground()
        .searchable(text: $query, prompt: "Поиск по чатам и @username")
        .task(id: searchNeedle) { await searchUsers(searchNeedle) }
        .overlay {
            if !searchNeedle.isEmpty && filteredChats.isEmpty && newPeople.isEmpty && userSearchError == nil {
                if isSearchingUsers { ProgressView() } else { ContentUnavailableView.search(text: query) }
            } else if viewModel.chats.isEmpty && !viewModel.isLoading && newMatches.isEmpty
                        && viewModel.incomingRequestsCount == 0 && viewModel.sentRequestsCount == 0 {
                ContentUnavailableView("Пока нет чатов", systemImage: "bubble.left.and.bubble.right", description: Text("Здесь появятся пары и переписка. Лайкайте анкеты в «Знакомствах» или нажмите ✎, чтобы написать по @username."))
            }
        }
        .confirmationDialog(
            chatPendingDeletion?.isClosed == true
                ? "Убрать чат у себя? У собеседника он останется, пока не истечёт срок хранения."
                : "Удалить чат вместе с перепиской у вас и у собеседника?",
            isPresented: Binding(get: { chatPendingDeletion != nil }, set: { if !$0 { chatPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: chatPendingDeletion
        ) { chat in
            Button(chat.isClosed ? "Убрать у себя" : "Удалить чат", role: .destructive) { Task { await viewModel.delete(chat) } }
        }
        .alert("Ошибка", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("Ок") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationTitle("Чаты")
    }

    @ViewBuilder
    private var listContent: some View {
        if searchNeedle.isEmpty && !showDeleted && !newMatches.isEmpty {
            NewMatchesStrip(matches: newMatches) { match in
                guard let chatId = match.chatId else { return }
                Task { openedChat = await viewModel.chat(withId: chatId) }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
        }

        if searchNeedle.isEmpty && !showDeleted && (viewModel.incomingRequestsCount > 0 || viewModel.sentRequestsCount > 0) {
            RequestsCard(incoming: viewModel.incomingRequestsCount, sent: viewModel.sentRequestsCount) {
                activeSheet = .requests
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
        }

        if searchNeedle.isEmpty {
            ChatTabs(showDeleted: $showDeleted, deletedCount: viewModel.chats.filter(\.isClosed).count)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
        }

        ForEach(visibleChats) { chat in
            chatButton(chat)
        }

        if searchNeedle.isEmpty && showDeleted {
            Text("Чаты пар, которые удалили вы или вас. Писать в них нельзя, переписка хранится 30 дней — чтобы можно было пожаловаться.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 24))
        }

        if !searchNeedle.isEmpty && (!newPeople.isEmpty || userSearchError != nil) {
            globalSearchSection
        }
    }

    private func chatButton(_ chat: Chat) -> some View {
        Button {
            openedChat = chat
        } label: {
            ChatRow(
                chat: chat,
                currentUserId: authViewModel.currentUser?.id,
                isTyping: viewModel.typingChatIds.contains(chat.id),
                draft: openedChat?.id == chat.id ? nil : drafts.drafts[chat.id]
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.appLine)
        // Макет «Чаты: свайпы»: вправо — «Прочитать» и «Закрепить», влево — «Удалить» и «Без звука».
        .swipeActions(edge: .leading) {
            if (chat.unreadCount ?? 0) > 0 {
                Button {
                    Task { await viewModel.markRead(chat) }
                } label: {
                    Label("Прочитать", systemImage: "checkmark.message")
                }
                .tint(Color(red: 0.43, green: 0.35, blue: 0.23))
            }
            Button {
                Task { await viewModel.setPinned(chat, pinned: chat.pinnedAt == nil) }
            } label: {
                Label(chat.pinnedAt == nil ? "Закрепить" : "Открепить", systemImage: chat.pinnedAt == nil ? "pin" : "pin.slash")
            }
            .tint(Color(red: 0.54, green: 0.43, blue: 0.25))
        }
        .swipeActions(edge: .trailing) {
            if chat.canDelete {
                Button(role: .destructive) { chatPendingDeletion = chat } label: {
                    Label(chat.isClosed ? "Убрать" : "Удалить", systemImage: "trash")
                }
                .tint(.brandDeep)
            }
            if !chat.isClosed {
                Button {
                    Task { await viewModel.toggleMute(chat) }
                } label: {
                    Label(chat.isMuted ? "Со звуком" : "Без звука", systemImage: chat.isMuted ? "bell" : "bell.slash")
                }
                .tint(Color(red: 0.29, green: 0.25, blue: 0.28))
            }
        }
    }

    private var globalSearchSection: some View {
        Section {
            ForEach(newPeople) { user in
                Button {
                    // Бот — не человек с анкетой: ему пишут сразу.
                    if user.isBot == true {
                        Task { openedChat = await viewModel.startChat(with: user) }
                    } else {
                        activeSheet = .person(user)
                    }
                } label: {
                    FoundUserRow(user: user)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.appLine)
            }
        } header: {
            Text("Глобальный поиск")
        } footer: {
            if let userSearchError { Text(userSearchError) }
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newChat:
            NewChatView { user, isSecret in
                activeSheet = nil
                Task {
                    if let chat = await viewModel.startChat(with: user, secret: isSecret) {
                        openedChat = chat
                    }
                }
            }
        case .person(let user):
            NavigationStack {
                PersonCardView(user: user) {
                    activeSheet = nil
                    Task { openedChat = await viewModel.startChat(with: user) }
                }
            }
        case .requests:
            NavigationStack {
                ChatRequestsView { chatId in
                    activeSheet = nil
                    Task {
                        openedChat = await viewModel.chat(withId: chatId)
                        await viewModel.loadRequestsCount()
                    }
                }
            }
        }
    }

    private var searchNeedle: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Пары, где ещё никто не написал: кружками сверху, чтобы не потерялись среди чатов.
    private var newMatches: [DatingMatch] {
        matches.matches.filter { !$0.hasMessages && $0.chatId != nil }
    }

    private func pair(forChatId chatId: String) -> DatingMatch? {
        matches.matches.first { $0.chatId == chatId }
    }

    /// Уже открытые чаты фильтруем на месте — по названию и @username.
    private var filteredChats: [Chat] {
        let needle = searchNeedle
        guard !needle.isEmpty else { return viewModel.chats }
        return viewModel.chats.filter { chat in
            chat.displayTitle.localizedCaseInsensitiveContains(needle)
                || chat.username?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    /// В поиске — все найденные чаты; без поиска — вкладка «Все» без удалённых пар или «Удалённые» только с ними.
    private var visibleChats: [Chat] {
        guard searchNeedle.isEmpty else { return filteredChats }
        return filteredChats.filter { $0.isClosed == showDeleted }
    }

    /// Найденные на сервере люди без тех, с кем личный чат уже есть в списке выше.
    private var newPeople: [User] {
        let peerIds = Set(filteredChats.filter { $0.type == .direct }.compactMap { $0.peer?.id })
        return foundUsers.filter { !peerIds.contains($0.id) }
    }

    private func searchUsers(_ needle: String) async {
        foundUsers = []
        userSearchError = nil
        isSearchingUsers = !needle.isEmpty
        guard !needle.isEmpty else { return }
        defer { if !Task.isCancelled { isSearchingUsers = false } }

        // Ждём паузу в наборе; новый символ меняет searchNeedle, и .task(id:) отменяет этот вызов.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        do {
            let users = try await APIClient.shared.searchUsers(query: needle)
            guard !Task.isCancelled else { return }
            foundUsers = users
        } catch {
            guard !Task.isCancelled else { return }
            userSearchError = error.localizedDescription
        }
    }
}

/// Первые сообщения и запросы — одной карточкой над чатами: «Вам написали» и «Ждут ответа».
/// Обе строки открывают общий ящик запросов, где ответ превращает сообщение в чат.
private struct RequestsCard: View {
    let incoming: Int
    let sent: Int
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if incoming > 0 {
                row(
                    systemImage: "tray.fill", iconColor: .white, iconBackground: AnyShapeStyle(.brandFill),
                    title: String(localized: "Вам написали"), subtitle: String(localized: "Ответьте — и откроется чат")
                ) {
                    CountBadge(count: incoming)
                }
            }
            if incoming > 0 && sent > 0 {
                Divider().overlay(Color.appLine)
            }
            if sent > 0 {
                row(
                    systemImage: "clock", iconColor: .champagne, iconBackground: AnyShapeStyle(Color.champagneSoft),
                    title: String(localized: "Ждут ответа"), subtitle: String(localized: "Вы написали первым")
                ) {
                    HStack(spacing: 10) {
                        Text("\(sent)")
                            .font(.app(.body, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }

    private func row<Trailing: View>(
        systemImage: String, iconColor: Color, iconBackground: AnyShapeStyle,
        title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(.body, weight: .semibold))
                    Text(subtitle)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// «Новые пары» — кружками в ряд: с ними ещё никто не написал, нажатие открывает чат пары.
private struct NewMatchesStrip: View {
    let matches: [DatingMatch]
    let onOpen: (DatingMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Новые пары ") + Text("\(matches.count)").foregroundStyle(Color.brand))
                    .font(.app(.body, weight: .bold))
                Spacer()
                Text("Напишите первым")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(matches) { match in
                        Button { onOpen(match) } label: {
                            VStack(spacing: 6) {
                                RingedAvatar(photoId: match.partner.photoId, size: 60, highlighted: true)
                                Text(match.partner.displayName)
                                    .font(.app(.footnote, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Новая пара: \(match.partner.displayName)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct FoundUserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName).font(.app(.body, weight: .semibold)).lineLimit(1)
                    if user.isBot == true { BotBadge() }
                }
                Text("@\(user.username)").font(.app(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ChatRow: View {
    let chat: Chat
    let currentUserId: String?
    /// Собеседник набирает текст — вместо последнего сообщения «печатает…».
    let isTyping: Bool
    /// Недописанное в этом чате — «Черновик: …» гранатом.
    let draft: String?

    private var unread: Int { chat.unreadCount ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            // У личных и секретных чатов — аватар собеседника, у групп и каналов — буква названия.
            AvatarView(avatarUrl: chat.peer?.avatarUrl, name: chat.displayTitle, size: 54)
                .overlay(alignment: .bottomTrailing) {
                    if chat.peer?.presence?.online == true {
                        Circle()
                            .fill(Color.online)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.appBackground, lineWidth: 2.5))
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("в сети")
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: chat.peer?.presence?.online)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if chat.type == .channel {
                        Image(systemName: "megaphone.fill").font(.app(.caption)).foregroundStyle(.secondary)
                    } else if chat.type == .secret {
                        Image(systemName: "lock.fill").font(.app(.caption)).foregroundStyle(Color.online)
                    }
                    Text(chat.displayTitle).font(.app(.body, weight: .bold)).lineLimit(1)
                    if chat.type == .direct, chat.participants.first?.isBot == true {
                        BotBadge()
                    }
                    if chat.isMuted {
                        Image(systemName: "bell.slash.fill").font(.app(.caption2)).foregroundStyle(.secondary)
                            .accessibilityLabel("Без звука")
                    }
                    Spacer(minLength: 8)
                    if chat.pinnedAt != nil {
                        Image(systemName: "pin.fill").font(.app(.caption2)).foregroundStyle(.secondary)
                            .accessibilityLabel("Закреплён")
                    }
                    if let date = chat.lastMessage?.createdAt {
                        // Есть непрочитанное — время гранатом и жирнее, как в макете.
                        Text(Self.timeLabel(for: date))
                            .font(.app(size: 12.5, weight: unread > 0 && !chat.isMuted ? .bold : .medium))
                            .foregroundStyle(unread > 0 && !chat.isMuted ? Color.brand : Color.secondary)
                    }
                }
                HStack(spacing: 8) {
                    subtitle
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.app(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(chat.isMuted ? Color.secondary : Color.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(chat.isMuted ? Color.appElevated : Color.brand, in: Capsule())
                            .contentTransition(.numericText(value: Double(unread)))
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Непрочитанных: \(unread)")
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: unread)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var subtitle: some View {
        if chat.isClosed {
            Label(closedSubtitle, systemImage: "lock")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if isTyping {
            HStack(spacing: 5) {
                Text("печатает")
                TypingDots(color: .brand, size: 4)
            }
            .font(.app(.subheadline))
            .foregroundStyle(Color.brand)
            .transition(.opacity)
        } else if let draft, !draft.isEmpty {
            (Text("Черновик: ").foregroundStyle(Color.brand).fontWeight(.semibold)
                + Text(draft.replacingOccurrences(of: "\n", with: " ")).foregroundStyle(.secondary))
                .font(.app(.subheadline))
                .lineLimit(1)
        } else if let last = chat.lastMessage, !last.previewText.isEmpty {
            HStack(spacing: 4) {
                if last.senderId == currentUserId, last.systemEvent == nil {
                    Text("Вы:").foregroundStyle(.primary)
                }
                Text(last.previewText).foregroundStyle(.secondary).lineLimit(1)
                if last.senderId == currentUserId, chat.type != .channel, let readAt = chat.readAt, readAt >= last.createdAt {
                    Image(systemName: "checkmark")
                        .overlay(Image(systemName: "checkmark").offset(x: 5))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.brand)
                        .padding(.trailing, 5)
                        .accessibilityLabel("Прочитано")
                }
            }
            .font(.app(.subheadline))
            .lineLimit(1)
        } else if let username = chat.username {
            Text("@\(username)").font(.app(.subheadline)).foregroundStyle(.secondary)
        }
    }

    private var closedSubtitle: String {
        guard let deletesAt = chat.deletesAt else { return String(localized: "Пара удалена") }
        return String(localized: "Пара удалена · исчезнет \(deletesAt.formatted(.dateTime.day().month(.abbreviated)))")
    }

    /// Сегодня — время, в этом году — день и месяц, раньше — полная дата (как в «Сообщениях»).
    private static func timeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Вчера")
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

struct BotBadge: View {
    var body: some View {
        Text("бот")
            .font(.app(.caption2, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

/// Переключатель «Все / Удалённые пары» под поиском (макеты «Чаты — вкладка „Все“» и «„Удалённые“»).
private struct ChatTabs: View {
    @Binding var showDeleted: Bool
    let deletedCount: Int

    var body: some View {
        HStack(spacing: 4) {
            tab(String(localized: "Все"), selected: !showDeleted) { showDeleted = false }
            tab(String(localized: "Удалённые пары"), count: deletedCount, selected: showDeleted) { showDeleted = true }
        }
        .padding(4)
        .frame(height: 40)
        .background(Color.appSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Какие чаты показать")
    }

    private func tab(_ title: String, count: Int = 0, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .font(.app(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.appElevated, in: Capsule())
                }
            }
            .font(.app(.subheadline, weight: selected ? .bold : .medium))
            .foregroundStyle(selected ? Color.brand : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color.brandSoft : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
