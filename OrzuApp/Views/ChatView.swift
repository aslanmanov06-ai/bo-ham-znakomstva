import PhotosUI
import QuickLook
import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    let onLeftChat: () -> Void
    @State private var draft = ""
    @State private var showGroupInfo = false
    @State private var partnerCard: User?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var previewURL: URL?
    @State private var showSafetyNumber = false
    @State private var showBlockConfirmation = false
    @State private var editingMessage: Message?
    @State private var messagePendingDeletion: Message?
    /// Таймер для фото, которое сейчас выбирают в галерее; nil — обычное фото.
    @State private var pendingViewTimer: Int?
    @State private var showVideoNoteRecorder = false
    @State private var timedPhoto: TimedPhotoPresentation?
    @State private var forwardSelection: ForwardSelection?
    /// Режим выделения сообщений для пересылки; nil — обычный режим.
    @State private var selectedIds: Set<String>?
    @State private var messageToReport: Message?
    @State private var showSearch = false
    @State private var showClearConfirmation = false
    @State private var showDeleteConfirmation = false
    /// Жалоба на собеседника из закрытого чата удалённой пары — не на отдельное сообщение, а на переписку.
    @State private var showPeerReport = false
    /// Сообщение, к которому нужно прокрутить: цитата, закреплённое или найденное поиском.
    @State private var scrollTarget: String?
    @StateObject private var voiceRecorder = VoiceRecorder()
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // body разбит на части: одним выражением компилятор не успевал вывести типы
    // («unable to type-check this expression in reasonable time»).
    var body: some View {
        chatWithDialogs
            .hiddenWhileScreenCaptured(viewModel.isSecret)
            .sheet(isPresented: $showPeerReport) {
                if let peer = viewModel.chat.peer {
                    NavigationStack { ReportUserView(userId: peer.id, displayName: peer.displayName) }
                }
            }
            .sheet(item: $messageToReport) { message in
                NavigationStack {
                    ReportUserView(userId: message.senderId, displayName: viewModel.displayName(of: message.senderId), messageId: message.id)
                }
            }
            .sheet(isPresented: $showSearch) {
                MessageSearchView(viewModel: viewModel) { message in
                    showSearch = false
                    show(messageId: message.id, loading: message)
                }
            }
            // Чат удалил собеседник или вы сами на другом устройстве — здесь больше нечего показывать.
            .onChange(of: viewModel.wasDeleted) { _, deleted in
                if deleted { onLeftChat() }
            }
            .onChange(of: draft) { _, text in
                if editingMessage == nil { viewModel.draftChanged(text) }
            }
            .sheet(isPresented: $showSafetyNumber) {
                SafetyNumberView(peerName: viewModel.chat.displayTitle, safetyNumber: viewModel.safetyNumber)
            }
            .sheet(item: $partnerCard) { peer in
                NavigationStack {
                    PersonCardView(user: peer)
                }
            }
            .sheet(isPresented: $showGroupInfo) {
                NavigationStack {
                    GroupInfoView(
                        viewModel: GroupInfoViewModel(chatId: viewModel.chat.id, currentUserId: viewModel.currentUserId),
                        onLeft: onLeftChat
                    )
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                let viewTimer = pendingViewTimer
                pendingViewTimer = nil
                Task { await viewModel.sendPhoto(item, viewTimerSec: viewTimer) }
            }
            .onChange(of: voiceRecorder.reachedLimit) { _, reached in
                if reached { finishVoiceRecording() }
            }
            .fullScreenCover(isPresented: $showVideoNoteRecorder) {
                VideoNoteRecorderView { recording in
                    Task { await viewModel.sendRecording(recording) }
                }
            }
            .fullScreenCover(item: $timedPhoto) { presentation in
                TimedPhotoViewer(presentation: presentation)
            }
            .onDisappear {
                VoicePlayer.shared.stop()
                voiceRecorder.cancel()
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    Task { await viewModel.sendFile(at: url) }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .quickLookPreview($previewURL)
            .task { await viewModel.loadHistory() }
    }

    /// Лента, панели сверху и снизу, навигационная панель.
    private var chatScreen: some View {
        messageList
            // Фон уходит под стеклянные панели — иначе им нечего преломлять.
            .background {
                ZStack {
                    AppBackground()
                    appearance.wallpaper.gradient.ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .top) {
                topBanners
            }
            .bottomGlassBar {
                bottomBar
            }
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle(viewModel.chat.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
    }

    /// Подтверждения удаления, очистки и блокировки, выбор чата для пересылки.
    private var chatWithDialogs: some View {
        chatScreen
            .confirmationDialog(
                "Удалить сообщение у всех? Оно исчезнет и у собеседников.",
                isPresented: Binding(get: { messagePendingDeletion != nil }, set: { if !$0 { messagePendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: messagePendingDeletion
            ) { message in
                Button("Удалить у всех", role: .destructive) { Task { await viewModel.delete(message, forEveryone: true) } }
            }
            .confirmationDialog(
                viewModel.canClearForEveryone ? "Очистить историю?" : "Очистить историю у себя? У остальных участников она останется.",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                if viewModel.canClearForEveryone {
                    Button("Очистить у себя", role: .destructive) { Task { await viewModel.clearHistory(forEveryone: false) } }
                    Button("Очистить у обоих", role: .destructive) { Task { await viewModel.clearHistory(forEveryone: true) } }
                } else {
                    Button("Очистить", role: .destructive) { Task { await viewModel.clearHistory(forEveryone: false) } }
                }
            }
            .confirmationDialog(
                "Удалить чат вместе с перепиской у вас и у собеседника?",
                isPresented: Binding(get: { showDeleteConfirmation && !viewModel.chat.isClosed }, set: { if !$0 { showDeleteConfirmation = false } }),
                titleVisibility: .visible
            ) {
                Button("Удалить чат", role: .destructive) {
                    Task {
                        if await viewModel.deleteChat() { onLeftChat() }
                    }
                }
            }
            .confirmationDialog(
                "Заблокировать \(viewModel.chat.displayTitle)? Вы не сможете писать и звонить друг другу. Разблокировать можно в Настройки → Приватность.",
                isPresented: $showBlockConfirmation,
                titleVisibility: .visible
            ) {
                Button("Заблокировать", role: .destructive) { Task { await viewModel.blockPeer() } }
            }
            .sheet(item: $forwardSelection) { selection in
                ForwardPickerView { chat in
                    let forwarded = await viewModel.forward(selection.messages, toChatId: chat.id)
                    if forwarded { selectedIds = nil }
                    return forwarded
                }
            }
            .confirmationDialog(
                removeClosedTitle,
                isPresented: Binding(get: { showDeleteConfirmation && viewModel.chat.isClosed }, set: { if !$0 { showDeleteConfirmation = false } }),
                titleVisibility: .visible
            ) {
                Button("Убрать у себя", role: .destructive) {
                    Task {
                        if await viewModel.deleteChat() { onLeftChat() }
                    }
                }
            }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.messages, id: \.rowId) { message in
                        if let systemText = viewModel.systemText(for: message) {
                            SystemEventRow(text: systemText)
                                .id(message.rowId)
                                .transition(.opacity)
                        } else {
                            messageRow(for: message)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                // Анимируется только добавление в конец ленты: вставка пузыря и сдвиг остальных вверх.
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.72), value: viewModel.arrivalCount)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // Только когда появилось новое последнее сообщение: реакция или правка в середине ленты не должны её прокручивать.
            // rowId, а не id: подтверждение своего сообщения сервером не считается новым сообщением.
            .onChange(of: viewModel.messages.last?.rowId) { _, lastRowId in
                guard let lastRowId, !viewModel.isShowingHistorySlice else { return }
                withAnimation(.snappy) { proxy.scrollTo(lastRowId, anchor: .bottom) }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                let rowId = viewModel.messages.first { $0.id == target }?.rowId ?? target
                withAnimation(.snappy) { proxy.scrollTo(rowId, anchor: .center) }
                scrollTarget = nil
            }
            // Секретный чат и фото с таймером: собеседник узнает о снимке экрана.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                viewModel.screenshotTaken(timedPhotoId: timedPhoto?.id)
            }
        }
    }

    private func messageRow(for message: Message) -> some View {
        selectableRow(for: message) {
            MessageBubble(
                message: message,
                isMine: viewModel.isMine(message),
                senderName: viewModel.senderName(for: message),
                replyAuthor: message.replyTo.map { viewModel.displayName(of: $0.senderId) },
                status: viewModel.status(of: message),
                isQuoted: message.id == viewModel.replyTo?.id || message.id == editingMessage?.id,
                reactions: message.reactionSummary(currentUserId: viewModel.currentUserId),
                timedPhotoState: viewModel.timedPhotoState(of: message),
                bubbleColor: appearance.bubbleColor.color,
                onOpenAttachment: openAttachment,
                onOpenTimedPhoto: { openTimedPhoto(message) },
                onOpenReply: { if let reply = message.replyTo { show(messageId: reply.id) } },
                onError: { viewModel.errorMessage = $0 }
            ) {
                messageMenu(for: message)
            }
        }
        .id(message.rowId)
        .transition(.bubbleArrival(isMine: viewModel.isMine(message), reduceMotion: reduceMotion))
    }

    private var topBanners: some View {
        VStack(spacing: 6) {
            if viewModel.isSecret {
                secretBanner
            }
            if let closedAt = viewModel.chat.closedAt {
                Label("Пара удалена \(Self.dayMonth.string(from: closedAt)) · переписка только для чтения", systemImage: "lock.fill")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.champagne)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.champagneSoft, in: Capsule())
            }
            if let stage = viewModel.pairStageName {
                Label("Вы пара · ступень «\(stage)» на пути к браку", systemImage: "heart.fill")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.champagne)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.champagneSoft, in: Capsule())
            }
            if let pinned = viewModel.pinnedMessage {
                pinnedBanner(for: pinned)
            }
            if viewModel.isShowingHistorySlice {
                Button("К последним сообщениям", systemImage: "arrow.down") {
                    Task { await viewModel.loadHistory() }
                }
                .font(.app(.footnote, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassSurface()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.app(.footnote))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassSurface()
            }
            if let selectedIds {
                selectionBar(selectedCount: selectedMessages(selectedIds).count)
            } else if viewModel.chat.isClosed {
                closedChatCard
            } else if viewModel.chat.canPost {
                Group {
                    if voiceRecorder.isRecording {
                        VStack(spacing: 0) {
                            // Голосовое тоже уходит ответом — цитата остаётся видна над записью.
                            if let quote = composerQuote {
                                quote
                                    .padding(.bottom, 3)
                                    .glassSurface(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                                    .padding(.horizontal)
                            }
                            VoiceRecordingBar(recorder: voiceRecorder, onCancel: voiceRecorder.cancel, onSend: finishVoiceRecording)
                        }
                    } else {
                        composer
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                .animation(.snappy, value: voiceRecorder.isRecording)
            } else {
                Text("Публиковать может только владелец канала")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassSurface()
                    .padding(.bottom, 8)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let peer = profilePeer {
                Button { partnerCard = peer } label: { chatHeader }
                    .buttonStyle(.plain)
                    .accessibilityHint("Открыть анкету")
            } else {
                chatHeader
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if viewModel.chat.canCall {
                Button { CallManager.shared.startCall(chat: viewModel.chat, video: false) } label: {
                    Image(systemName: "phone")
                }
                .accessibilityLabel("Аудиозвонок")
                Button { CallManager.shared.startCall(chat: viewModel.chat, video: true) } label: {
                    Image(systemName: "video")
                }
                .accessibilityLabel("Видеозвонок")
            }
            switch viewModel.chat.type {
            case .group, .channel:
                Button { showGroupInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Информация")
            case .secret:
                Button { showSafetyNumber = true } label: { Image(systemName: "lock.shield") }
                    .accessibilityLabel("Код безопасности")
            case .direct:
                EmptyView()
            }
            chatMenu
        }
    }

    /// Аватар и имя по центру навигационной панели, как в «Сообщениях».
    private var chatHeader: some View {
        let chat = viewModel.chat
        return HStack(spacing: 8) {
            AvatarView(avatarUrl: chat.peer?.avatarUrl, name: chat.displayTitle, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(chat.displayTitle).font(.app(.body, weight: .semibold)).lineLimit(1)
                    if viewModel.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Без звука")
                    }
                }
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.app(.caption2))
                        .foregroundStyle(isPeerOnline ? Color.brand : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «в сети» и «печатает…» — гранатом: живой собеседник заметнее серого «был вчера».
    private var isPeerOnline: Bool {
        !viewModel.typingUserIds.isEmpty || viewModel.peerPresence?.online == true
    }

    /// Собеседник в личном или секретном чате: по нажатию на заголовок открывается его анкета. У бота анкеты нет.
    private var profilePeer: User? {
        let chat = viewModel.chat
        guard chat.type == .direct || chat.type == .secret, let peer = chat.peer, peer.isBot != true else { return nil }
        return peer
    }

    private var headerSubtitle: String? {
        if viewModel.chat.isClosed { return String(localized: "пара удалена") }
        if let status = viewModel.headerStatus { return status }
        switch viewModel.chat.type {
        case .secret: return String(localized: "секретный чат")
        case .channel: return String(localized: "канал")
        case .group: return String(localized: "группа")
        case .direct: return viewModel.chat.participants.first?.isBot == true ? String(localized: "бот") : nil
        }
    }

    /// Вместо поля ввода в чате удалённой пары (макет «Чат удалённой пары»).
    private var closedChatCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Писать сюда больше нельзя")
                        .font(.app(.subheadline, weight: .semibold))
                    Text(closedChatHint)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button("Пожаловаться") { showPeerReport = true }
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.appElevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
                    .disabled(viewModel.chat.peer == nil)
                Button("Убрать у себя") { showDeleteConfirmation = true }
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .appCard(cornerRadius: 20, padding: nil)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var closedChatHint: String {
        let deletes = viewModel.chat.deletesAt.map { String(localized: "Чат исчезнет \(Self.dayMonth.string(from: $0)). ") } ?? ""
        return deletes + String(localized: "Если вас обидели — пожалуйтесь, модератор увидит переписку.")
    }

    private var removeClosedTitle: String {
        guard let deletesAt = viewModel.chat.deletesAt else { return String(localized: "Убрать чат у себя? У собеседника он останется.") }
        return String(localized: "Убрать чат у себя? У собеседника он останется до \(Self.dayMonth.string(from: deletesAt)).")
    }

    /// «25 сентября» — даты закрытия и удаления чата удалённой пары.
    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private var chatMenu: some View {
        Menu {
            if viewModel.canSearch {
                Button("Поиск", systemImage: "magnifyingglass") { showSearch = true }
            }
            muteMenu
            if viewModel.chat.type == .channel, let username = viewModel.chat.username {
                ShareLink(item: DeepLink.channel(username: username).url) {
                    Label("Поделиться каналом", systemImage: "square.and.arrow.up")
                }
            }
            Button("Очистить историю", systemImage: "eraser") { showClearConfirmation = true }
            if viewModel.chat.canDelete {
                Button(viewModel.chat.isClosed ? "Убрать у себя" : "Удалить чат", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
                Button("Заблокировать", systemImage: "hand.raised", role: .destructive) { showBlockConfirmation = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Ещё")
    }

    private var muteMenu: some View {
        Menu {
            Section(muteStatus) {
                ForEach(MuteOption.allCases) { option in
                    Button(option.title) { Task { await viewModel.setMute(option) } }
                }
                if viewModel.isMuted {
                    Button("Включить звук", systemImage: "bell") { Task { await viewModel.setMute(nil) } }
                }
            }
        } label: {
            Label(viewModel.isMuted ? "Звук выключен" : "Без звука", systemImage: "bell.slash")
        }
    }

    private var muteStatus: String {
        guard viewModel.isMuted, let until = viewModel.mutedUntil else { return String(localized: "Уведомления о сообщениях этого чата") }
        if until.isEffectivelyForever { return String(localized: "Без звука навсегда") }
        return String(localized: "Без звука до \(until.formatted(Calendar.current.isDateInToday(until) ? .dateTime.hour().minute() : .dateTime.day().month().hour().minute()))")
    }

    /// В режиме выделения пузырь не реагирует на нажатия (не открывает вложения), а строка целиком отмечает сообщение.
    @ViewBuilder
    private func selectableRow<Bubble: View>(for message: Message, @ViewBuilder bubble: () -> Bubble) -> some View {
        if let selectedIds {
            let canSelect = viewModel.canForward(message)
            let isSelected = selectedIds.contains(message.id)
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.app(.title3))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .opacity(canSelect ? 1 : 0.3)
                bubble().allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(of: message) }
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        } else {
            bubble()
        }
    }

    private func toggleSelection(of message: Message) {
        guard var ids = selectedIds, viewModel.canForward(message) else { return }
        if ids.contains(message.id) {
            ids.remove(message.id)
        } else if selectedMessages(ids).count >= ChatViewModel.maxForwardBatch {
            viewModel.errorMessage = String(localized: "За раз можно переслать не больше \(ChatViewModel.maxForwardBatch) сообщений")
            return
        } else {
            ids.insert(message.id)
        }
        selectedIds = ids
    }

    /// Выбранные в порядке переписки. Удалённые за это время сами выпадают: их больше нет в ленте.
    private func selectedMessages(_ ids: Set<String>) -> [Message] {
        viewModel.messages.filter { ids.contains($0.id) }
    }

    private func selectionBar(selectedCount: Int) -> some View {
        HStack {
            Button("Отмена") { selectedIds = nil }
            Spacer()
            Text("Выбрано: \(selectedCount)").font(.app(.subheadline, weight: .semibold))
            Spacer()
            Button("Переслать", systemImage: "arrowshape.turn.up.right") {
                guard let selectedIds else { return }
                forwardSelection = ForwardSelection(messages: selectedMessages(selectedIds))
            }
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface()
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// Прокрутить к сообщению; если его нет среди загруженных — подгрузить фрагмент переписки с ним.
    private func show(messageId: String, loading message: Message? = nil) {
        if viewModel.messages.contains(where: { $0.id == messageId }) {
            scrollTarget = messageId
            return
        }
        guard let message else {
            viewModel.errorMessage = String(localized: "Сообщение выше по переписке — найдите его через поиск")
            return
        }
        Task {
            if await viewModel.reveal(message) { scrollTarget = messageId }
        }
    }

    private func pinnedBanner(for message: Message) -> some View {
        HStack(spacing: 10) {
            Button {
                show(messageId: message.id, loading: message)
            } label: {
                HStack(spacing: 10) {
                    Rectangle().fill(Color.accentColor).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Закреплённое сообщение").font(.app(.caption, weight: .bold)).foregroundStyle(Color.accentColor)
                        Text(message.previewText).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if viewModel.chat.canPost {
                Button {
                    Task { await viewModel.pin(nil) }
                } label: {
                    Image(systemName: "pin.slash").font(.app(.footnote))
                }
                .accessibilityLabel("Открепить")
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    private var secretBanner: some View {
        VStack(spacing: 8) {
            if viewModel.peerKeyChanged {
                Text("Ключ шифрования собеседника изменился. Так бывает после переустановки приложения — но так же выглядела бы и подмена ключа сервером. Сверьте код безопасности с собеседником лично.")
                    .font(.app(.footnote))
                HStack {
                    Button("Код безопасности") { showSafetyNumber = true }
                    Spacer()
                    Button("Доверять новому ключу") { Task { await viewModel.acceptChangedPeerKey() } }
                        .bold()
                }
                .font(.app(.footnote))
            } else {
                Label("Сообщения видны только на ваших двух устройствах", systemImage: "lock.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: viewModel.peerKeyChanged ? 20 : 16, style: .continuous),
            tint: viewModel.peerKeyChanged ? .orange.opacity(0.3) : nil
        )
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var composer: some View {
        ComposerBar(
            text: $draft,
            placeholder: String(localized: "Сообщение"),
            canSend: canSend,
            sendSystemImage: editingMessage == nil ? "arrow.up" : "checkmark",
            // В секретном чате вложений нет — там кнопка всегда «Отправить».
            idleAction: viewModel.isSecret ? nil : ComposerIdleAction(
                systemImage: "mic",
                accessibilityLabel: "Записать голосовое",
                action: startVoiceRecording
            ),
            isIdle: showsMediaButtons,
            onSend: submit
        ) {
            composerQuote
        } accessory: {
            // Вложения хранятся на сервере незашифрованными — в секретном чате их нет.
            if !viewModel.isSecret, editingMessage == nil {
                attachmentMenu
            }
        } inlineTrailing: {
            if showsMediaButtons {
                Button(action: startVideoNote) { ComposerInlineIcon(systemImage: "video.circle") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Записать видеосообщение")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        // Цитата выезжает из поля, когда ответ или правку выбирают в меню сообщения.
        .animation(.snappy, value: viewModel.replyTo?.id)
        .animation(.snappy, value: editingMessage?.id)
    }

    /// Пока поле пустое, вместо «отправить» — запись голосового и «кружка». В секретном чате вложений нет.
    private var showsMediaButtons: Bool {
        draft.isEmpty && editingMessage == nil && !viewModel.isSecret && !viewModel.isUploading
    }

    /// Цитата над полем. Правка и ответ не бывают одновременно: начало одного сбрасывает другое.
    private var composerQuote: ComposerQuote? {
        if let editingMessage {
            return ComposerQuote(title: String(localized: "Редактирование"), text: editingMessage.previewText, cancelLabel: "Отменить редактирование") {
                self.editingMessage = nil
                draft = ""
            }
        }
        if let replyTo = viewModel.replyTo {
            return ComposerQuote(
                title: String(localized: "Ответ: \(viewModel.displayName(of: replyTo.senderId))"),
                text: replyTo.previewText,
                cancelLabel: "Отменить ответ"
            ) {
                viewModel.replyTo = nil
            }
        }
        return nil
    }

    /// Запись во время звонка перехватила бы у него микрофон и аудиосессию.
    private var isInCall: Bool {
        CallManager.shared.state != .idle
    }

    private func startVoiceRecording() {
        guard !isInCall else {
            viewModel.errorMessage = String(localized: "Во время звонка запись недоступна")
            return
        }
        VoicePlayer.shared.stop()
        Task {
            do {
                try await voiceRecorder.start()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func finishVoiceRecording() {
        guard let recording = voiceRecorder.finish() else { return }
        Task { await viewModel.sendRecording(recording) }
    }

    private func startVideoNote() {
        guard !isInCall else {
            viewModel.errorMessage = String(localized: "Во время звонка запись недоступна")
            return
        }
        VoicePlayer.shared.stop()
        showVideoNoteRecorder = true
    }

    private func openTimedPhoto(_ message: Message) {
        guard let attachment = message.attachment, let viewTimerSec = message.viewTimerSec else { return }
        Task {
            guard let opening = await viewModel.openTimedPhoto(message), opening.expiresAt > Date() else { return }
            timedPhoto = TimedPhotoPresentation(
                id: message.id, attachmentId: attachment.id, viewTimerSec: viewTimerSec, expiresAt: opening.expiresAt
            )
        }
    }

    /// При правке подпись к фото можно стереть целиком — у сообщения останется вложение.
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || editingMessage?.attachment != nil) && !viewModel.peerKeyChanged
    }

    private func submit() {
        if let editingMessage {
            let text = draft
            Task { await viewModel.edit(editingMessage, text: text) }
            self.editingMessage = nil
        } else {
            viewModel.send(text: draft)
        }
        draft = ""
    }

    @ViewBuilder
    private func messageMenu(for message: Message) -> some View {
        // Пока сервер не подтвердил отправку, у сообщения временный id — действовать с ним нельзя.
        let isConfirmed = !viewModel.pendingIds.contains(message.id)
        if isConfirmed {
            ControlGroup {
                ForEach(MessageReaction.allowed, id: \.self) { emoji in
                    Button { Task { await viewModel.toggleReaction(emoji, on: message) } } label: { Text(emoji) }
                }
            }
            .controlGroupStyle(.palette)
        }
        if isConfirmed, viewModel.chat.canPost, !viewModel.peerKeyChanged {
            Button("Ответить", systemImage: "arrowshape.turn.up.left") {
                editingMessage = nil
                viewModel.replyTo = message
            }
        }
        if !message.text.isEmpty {
            Button("Скопировать", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
        }
        if viewModel.canForward(message) {
            Button("Переслать", systemImage: "arrowshape.turn.up.right") { forwardSelection = ForwardSelection(messages: [message]) }
            if selectedIds == nil {
                Button("Выбрать", systemImage: "checkmark.circle") {
                    editingMessage = nil
                    viewModel.replyTo = nil
                    selectedIds = [message.id]
                }
            }
        }
        if viewModel.canPin(message) {
            if viewModel.pinnedMessage?.id == message.id {
                Button("Открепить", systemImage: "pin.slash") { Task { await viewModel.pin(nil) } }
            } else {
                Button("Закрепить", systemImage: "pin") { Task { await viewModel.pin(message) } }
            }
        }
        if viewModel.canEdit(message) {
            Button("Редактировать", systemImage: "pencil") {
                viewModel.replyTo = nil
                editingMessage = message
                draft = message.text
            }
        }
        if viewModel.canReport(message) {
            Button("Пожаловаться", systemImage: "exclamationmark.bubble") { messageToReport = message }
        }
        if isConfirmed {
            Button("Удалить у себя", systemImage: "trash", role: .destructive) {
                Task { await viewModel.delete(message, forEveryone: false) }
            }
        }
        if viewModel.canDeleteForEveryone(message) {
            Button("Удалить у всех", systemImage: "trash.slash", role: .destructive) { messagePendingDeletion = message }
        }
    }

    private var attachmentMenu: some View {
        Menu {
            // Каждый путь к галерее задаёт таймер явно: отменённый выбор «с таймером» не должен повлиять на обычное фото.
            Button {
                pendingViewTimer = nil
                showPhotoPicker = true
            } label: {
                Label("Фото", systemImage: "photo")
            }
            if viewModel.canSendTimedPhoto {
                Menu {
                    ForEach(Message.viewTimerOptions, id: \.self) { seconds in
                        Button("\(seconds) секунд") {
                            pendingViewTimer = seconds
                            showPhotoPicker = true
                        }
                    }
                } label: {
                    Label("Фото с таймером", systemImage: "flame")
                }
            }
            Button { showFileImporter = true } label: { Label("Файл", systemImage: "doc") }
        } label: {
            if viewModel.isUploading {
                ProgressView()
                    .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
            } else {
                ComposerInlineIcon(systemImage: "plus", filled: true)
            }
        }
        .disabled(viewModel.isUploading)
        .accessibilityLabel("Вложение")
    }

    private func openAttachment(_ attachment: Attachment) {
        Task { previewURL = await viewModel.previewURL(for: attachment) }
    }
}

/// Что пересылаем: одно сообщение из меню или несколько выбранных.
/// Служебная строка по центру ленты: без меню, реакций и выделения — это не чьё-то сообщение.
private struct SystemEventRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "camera.viewfinder")
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

private struct ForwardSelection: Identifiable {
    let id = UUID()
    let messages: [Message]
}

private struct MessageBubble<MenuItems: View>: View {
    let message: Message
    let isMine: Bool
    let senderName: String?
    /// Автор цитаты, если это ответ.
    let replyAuthor: String?
    /// nil — не своё сообщение или канал: галочки не показываем.
    let status: DeliveryStatus?
    /// На это сообщение сейчас отвечают или его правят — пузырь подсвечен гранатовой рамкой.
    let isQuoted: Bool
    let reactions: [ReactionSummary]
    /// nil — не фото с таймером.
    let timedPhotoState: TimedPhotoState?
    let bubbleColor: Color
    let onOpenAttachment: (Attachment) -> Void
    let onOpenTimedPhoto: () -> Void
    let onOpenReply: () -> Void
    let onError: (String) -> Void
    /// Пункты меню по долгому нажатию: меню висит на самом пузыре, чтобы подсвечивался он, а не вся строка.
    @ViewBuilder var menuItems: MenuItems

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 4) {
                if let senderName {
                    Text(senderName).font(.app(.caption, weight: .bold)).foregroundStyle(Color.accentColor)
                }
                if let forwardedFrom = message.forwardedFromName {
                    Label("Переслано от \(forwardedFrom)", systemImage: "arrowshape.turn.up.right")
                        .font(.app(.caption))
                        .foregroundStyle(isMine ? Color.white.opacity(0.8) : Color.secondary)
                }
                if let reply = message.replyTo {
                    replyQuote(reply)
                }
                if let attachment = message.attachment {
                    attachmentContent(attachment)
                }
                // Время и галочки — в правом нижнем углу, как в «Сообщениях» и Telegram.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    if !message.text.isEmpty {
                        Text(message.text)
                    }
                    footer
                        .frame(maxWidth: message.text.isEmpty ? .infinity : nil, alignment: .trailing)
                }
                if !reactions.isEmpty {
                    ReactionChips(reactions: reactions, isMine: isMine)
                }
            }
            .foregroundStyle(isMine ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isMine ? bubbleColor : Color.appSurface, in: bubbleShape)
            // Пузырь собеседника на светлом фоне без границы сливается с ним.
            .overlay { if !isMine { bubbleShape.stroke(Color.appLine, lineWidth: 1) } }
            .overlay {
                if isQuoted {
                    bubbleShape.stroke(Color.brand, lineWidth: 1.5)
                    bubbleShape.stroke(Color.brand.opacity(0.14), lineWidth: 8).padding(-4)
                }
            }
            .animation(.snappy, value: isQuoted)
            .contentShape(.contextMenuPreview, bubbleShape)
            .contextMenu { menuItems }

            if !isMine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private func attachmentContent(_ attachment: Attachment) -> some View {
        if let timedPhotoState, let viewTimerSec = message.viewTimerSec {
            TimedPhotoView(attachment: attachment, state: timedPhotoState, viewTimerSec: viewTimerSec, onOpen: onOpenTimedPhoto)
        } else if attachment.isProcessing && !isMine {
            // Сервер отдаст файл собеседнику только после перекодирования — до этого качать нечего.
            ProcessingAttachmentView(kind: attachment.kind)
        } else {
            switch attachment.kind {
            // .video — ролик анкеты знакомств; в чат он не попадает, но если пришёл, показываем как файл.
            case .image, .file, .video:
                Button {
                    onOpenAttachment(attachment)
                } label: {
                    if attachment.kind == .image {
                        AttachmentImageView(attachment: attachment)
                    } else {
                        AttachmentFileView(attachment: attachment)
                    }
                }
                .buttonStyle(.plain)
            case .voice:
                VoiceMessageView(attachment: attachment, isMine: isMine, onError: onError)
            case .videoNote:
                VideoNoteView(attachment: attachment)
            }
        }
    }

    private func replyQuote(_ reply: ReplyPreview) -> some View {
        Button(action: onOpenReply) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(isMine ? Color.white : Color.accentColor)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(replyAuthor ?? "").font(.app(.caption, weight: .bold))
                    Text(reply.previewText).font(.app(.caption)).lineLimit(1)
                }
                .foregroundStyle(isMine ? Color.white.opacity(0.9) : Color.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ответ на сообщение \(replyAuthor ?? ""): \(reply.previewText)")
    }

    private var footer: some View {
        HStack(spacing: 3) {
            if message.editedAt != nil {
                Text("изм.")
            }
            Text(message.createdAt, style: .time)
            if let status {
                DeliveryStatusIcon(status: status)
            }
        }
        .font(.app(.caption2))
        .foregroundStyle(isMine ? Color.white.opacity(0.7) : Color.secondary)
    }

    /// Скруглённый «хвост» со стороны отправителя: свои — справа внизу, чужие — слева внизу.
    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isMine ? 18 : 6,
            bottomTrailingRadius: isMine ? 6 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }
}

/// Появление нового пузыря: свой поднимается от поля ввода и садится с лёгкой отдачей, чужой выплывает слева снизу.
/// С «Уменьшением движения» — только прозрачность.
private struct BubbleArrivalModifier: ViewModifier {
    let isHidden: Bool
    let isMine: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let moves = isHidden && !reduceMotion
        content
            .opacity(isHidden ? 0 : 1)
            .scaleEffect(moves ? (isMine ? 0.92 : 0.96) : 1, anchor: isMine ? .bottomTrailing : .bottomLeading)
            .offset(y: moves ? (isMine ? 40 : 16) : 0)
    }
}

extension AnyTransition {
    fileprivate static func bubbleArrival(isMine: Bool, reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BubbleArrivalModifier(isHidden: true, isMine: isMine, reduceMotion: reduceMotion),
                identity: BubbleArrivalModifier(isHidden: false, isMine: isMine, reduceMotion: reduceMotion)
            ),
            removal: .opacity
        )
    }
}

/// Часы — ещё отправляется, одна галочка — на сервере, две — доставлено, две яркие — прочитано.
/// Смена статуса — с отскоком: новая иконка вырастает на месте старой.
private struct DeliveryStatusIcon: View {
    let status: DeliveryStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            icon
                .id(status)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.55), value: status)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var icon: some View {
        Group {
            switch status {
            case .sending:
                Image(systemName: "clock")
            case .sent:
                Image(systemName: "checkmark")
            case .delivered, .read:
                HStack(spacing: -5) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
            }
        }
        .fontWeight(status == .read ? .bold : .regular)
        .foregroundStyle(status == .read ? Color.white : Color.white.opacity(0.7))
    }

    private var accessibilityText: String {
        switch status {
        case .sending: return String(localized: "Отправляется")
        case .sent: return String(localized: "Отправлено")
        case .delivered: return String(localized: "Доставлено")
        case .read: return String(localized: "Прочитано")
        }
    }
}

/// Реакции под текстом: эмодзи и число, своя подсвечена. Переносятся на новую строку, если не влезают.
private struct ReactionChips: View {
    let reactions: [ReactionSummary]
    let isMine: Bool

    var body: some View {
        ReactionsFlowLayout(spacing: 4) {
            ForEach(reactions, id: \.emoji) { reaction in
                HStack(spacing: 3) {
                    Text(reaction.emoji)
                    if reaction.count > 1 {
                        Text("\(reaction.count)").font(.app(.caption).monospacedDigit().weight(.semibold))
                    }
                }
                .font(.app(.callout))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chipBackground(highlighted: reaction.isMine), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(reaction.emoji) \(reaction.count)\(reaction.isMine ? String(localized: ", ваша реакция") : "")")
            }
        }
    }

    private func chipBackground(highlighted: Bool) -> Color {
        if isMine {
            return .white.opacity(highlighted ? 0.35 : 0.18)
        }
        return highlighted ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08)
    }
}

/// Раскладка «строками с переносом», как у тегов: в SwiftUI готовой нет.
private struct ReactionsFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if widthWithItem > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private struct SafetyNumberView: View {
    let peerName: String
    let safetyNumber: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield").font(.system(size: 56)).foregroundStyle(Color.accentColor)
                if let safetyNumber {
                    Text(safetyNumber)
                        .font(.system(.title3, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                }
                Text("Сравните этот код с кодом на телефоне «\(peerName)» — лично или по звонку. Если коды совпадают, никто посередине (включая сервер) не может читать переписку.")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .navigationTitle("Код безопасности")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
