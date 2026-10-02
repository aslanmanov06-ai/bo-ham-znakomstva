import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var appStatus = AppStatus.shared
    @ObservedObject private var appLock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else if authViewModel.isRestoringSession {
                RestoringSessionView()
            } else {
                LoginView()
            }
        }
        // Служебные экраны накрывают приложение, не пересоздавая его: после обслуживания всё на своих местах.
        .overlay { appWideScreen }
        .overlay {
            if authViewModel.isAuthenticated && (appLock.isLocked || (appLock.isEnabled && scenePhase != .active)) {
                AppLockView(appLock: appLock)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: appLock.lockIfEnabled()
            case .active: Task { await appLock.unlock() }
            default: break
            }
        }
        .task { await appStatus.refresh() }
        .fullScreenCover(isPresented: isCallActive) {
            CallOverlayView()
        }
        .preferredColorScheme(appearance.theme.colorScheme)
    }

    /// Обновление важнее блокировки (старая версия может не понять новых ответов сервера), блокировка — обслуживания.
    @ViewBuilder
    private var appWideScreen: some View {
        if appStatus.updateRequired, let minimum = appStatus.config?.minIosVersion {
            UpdateRequiredView(minimumVersion: minimum)
        } else if let ban = appStatus.ban {
            AccountBannedView(notice: ban) {
                appStatus.dismissBan()
                Task { await authViewModel.logout() }
            }
        } else if appStatus.isUnderMaintenance {
            MaintenanceView(status: appStatus)
        }
    }

    private var isCallActive: Binding<Bool> {
        Binding(
            get: {
                if case .idle = callManager.state { return false }
                return true
            },
            set: { _ in }
        )
    }
}

/// Аккаунт на устройстве есть, а профиль ещё не пришёл с сервера. Выход — на случай, если сервер недоступен долго.
private struct RestoringSessionView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(network.isOnline ? "Подключаемся к серверу…" : "Ожидание сети…")
                .foregroundStyle(.secondary)
            Button("Выйти из аккаунта") {
                Task { await authViewModel.logout() }
            }
            .font(.app(.footnote))
            .padding(.top, 24)
        }
    }
}

/// Состояние связи над вкладками: «Нет сети» или «Соединение…», пока сокет не подключился к серверу.
private struct ConnectionBanner: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isOnline {
                ProgressView().controlSize(.mini)
                Text("Соединение…")
            } else {
                Image(systemName: "wifi.slash")
                Text("Нет сети")
            }
        }
        .font(.app(.footnote, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// Основная навигация: в iOS 26 панель вкладок становится плавающей стеклянной и сворачивается при прокрутке.
private struct MainTabView: View {
    private enum AppTab {
        case dating, browse, roulette, chats, profile
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var push = PushManager.shared
    @ObservedObject private var safetyAlerts = SafetyAlertsViewModel.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var socket = WebSocketClient.shared
    @State private var selection = AppTab.dating
    /// Анкета — часть профиля: её правят и во вкладках знакомств, и в «Моём профиле», поэтому модель одна на все.
    @StateObject private var dating = DatingViewModel()
    /// Рулетка живёт на уровне вкладок: уход с вкладки или в фон заканчивает разговор (камера и сокет не нужны в фоне).
    @StateObject private var roulette = RouletteViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// «Соединение…» показываем не сразу: обычно сокет подключается за доли секунды, и плашка только мигнула бы.
    @State private var isConnectingTooLong = false
    /// Человек или канал из открытой ссылки.
    @State private var linkedUser: User?
    @State private var linkedChannel: PublicChannel?
    @State private var linkError: String?

    private static let connectingBannerDelay: Duration = .seconds(1)

    var body: some View {
        Group {
            if dating.needsOnboarding {
                ProfileOnboardingView(dating: dating)
            } else {
                content
            }
        }
        .task { await dating.load() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !network.isOnline || isConnectingTooLong {
                ConnectionBanner(isOnline: network.isOnline)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tabs
        }
        .animation(.default, value: network.isOnline)
        .animation(.default, value: isConnectingTooLong)
        .task(id: socket.isReady) {
            isConnectingTooLong = false
            guard !socket.isReady else { return }
            try? await Task.sleep(for: Self.connectingBannerDelay)
            guard !Task.isCancelled else { return }
            isConnectingTooLong = true
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            DatingTabView(dating: dating)
                .tabItem { Label("Знакомства", systemImage: "heart.fill") }
                .tag(AppTab.dating)

            DatingBrowseTabView(dating: dating)
                .tabItem { Label("Анкеты", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.browse)

            RouletteTabView(dating: dating, roulette: roulette) { selection = .profile }
                .tabItem { Label("Рулетка", systemImage: "shuffle") }
                .tag(AppTab.roulette)

            ChatListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.chats)

            NavigationStack { MyProfileView(dating: dating) { authViewModel.updateCurrentUser($0) } }
                .tabItem { Label("Мой профиль", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        .tabBarMinimizesOnScroll()
        .onChange(of: selection) { _, tab in
            if tab != .roulette { roulette.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { roulette.stop() }
        }
        // Нажали на push о сообщении — чат откроет ChatListView, но вкладка должна быть видна.
        .onChange(of: push.pendingChatId) { _, chatId in
            if chatId != nil { selection = .chats }
        }
        // «Написать» из анкеты — переписка живёт в мессенджере.
        .onChange(of: push.pendingConversation) { _, user in
            if user != nil { selection = .chats }
        }
        // Push о первом сообщении, встрече или «Пути к браку» — чата ещё нет, открываем знакомства.
        .onChange(of: push.pendingDating) { _, pending in
            guard pending else { return }
            selection = .dating
            push.pendingDating = false
        }
        // Просьба модератора о селфи открывается в «Моём профиле».
        .onChange(of: push.pendingSelfieRequest) { _, pending in
            if pending { selection = .profile }
        }
        .task(id: push.pendingDeepLink) {
            guard let link = push.pendingDeepLink else { return }
            push.pendingDeepLink = nil
            await open(link)
        }
        .sheet(item: $linkedUser) { user in
            NavigationStack {
                PersonCardView(user: user) {
                    linkedUser = nil
                    push.pendingConversation = user
                }
            }
        }
        .alert(
            linkedChannel?.title ?? "",
            isPresented: Binding(get: { linkedChannel != nil }, set: { if !$0 { linkedChannel = nil } }),
            presenting: linkedChannel
        ) { channel in
            Button("Подписаться") { Task { await join(channel) } }
            Button("Отмена", role: .cancel) {}
        } message: { channel in
            Text("Канал · \(channel.subscriberCount) подписчиков")
        }
        .alert("Ссылка не открылась", isPresented: .constant(linkError != nil)) {
            Button("Ок") { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
        .task(id: push.pendingSosId) {
            guard let sosId = push.pendingSosId else { return }
            push.pendingSosId = nil
            await safetyAlerts.open(alertId: sosId)
        }
        // Тревога доверенного контакта важнее текущего экрана — показываем её поверх вкладок.
        .fullScreenCover(item: $safetyAlerts.incomingAlert) { alert in
            SosAlertView(alert: alert, signalLost: safetyAlerts.signalLostAlertIds.contains(alert.id)) { safetyAlerts.incomingAlert = nil }
        }
        .alert(safetyAlerts.sanction?.title ?? "", isPresented: .constant(safetyAlerts.sanction != nil)) {
            Button("Понятно") { safetyAlerts.sanction = nil }
        } message: {
            Text(safetyAlerts.sanction?.reason ?? "")
        }
        // Текст как в push о встрече: если что-то пойдёт не так, доверенный контакт уже знает, где искать.
        .alert(
            "\(safetyAlerts.sharedMeeting?.displayName ?? "") идёт на встречу",
            isPresented: Binding(get: { safetyAlerts.sharedMeeting != nil }, set: { if !$0 { safetyAlerts.sharedMeeting = nil } }),
            presenting: safetyAlerts.sharedMeeting
        ) { _ in
            Button("Понятно") { safetyAlerts.sharedMeeting = nil }
        } message: { meeting in
            Text("Кто: \(meeting.withDisplayName)\nГде: \(meeting.place)\nКогда: \(meeting.startsAt.formatted(date: .long, time: .shortened))")
        }
    }
}

extension MainTabView {
    /// Поиск — по точному username: ссылка ведёт на конкретного человека или канал, а не на похожие.
    fileprivate func open(_ link: DeepLink) async {
        do {
            switch link {
            case .user(let username):
                let users = try await APIClient.shared.searchUsers(query: username)
                guard let user = users.first(where: { $0.username.lowercased() == username }) else {
                    linkError = String(localized: "Человек не найден — возможно, он сменил username или скрыл профиль.")
                    return
                }
                linkedUser = user
            case .channel(let username):
                let channels = try await APIClient.shared.searchChannels(query: username)
                guard let channel = channels.first(where: { $0.username?.lowercased() == username }) else {
                    linkError = String(localized: "Канал не найден.")
                    return
                }
                linkedChannel = channel
            }
        } catch {
            linkError = error.localizedDescription
        }
    }

    /// Подписка открывает канал так же, как push о сообщении: через вкладку «Чаты».
    fileprivate func join(_ channel: PublicChannel) async {
        do {
            try await APIClient.shared.subscribeToChannel(chatId: channel.id)
            push.pendingChatId = channel.id
        } catch {
            linkError = error.localizedDescription
        }
    }
}

/// Обязательный шаг после регистрации (и для тех, кто вошёл до этого правила): правила сообщества → анкета →
/// хотя бы одно фото. Когда фото добавлено, RootView сам покажет вкладки.
private struct ProfileOnboardingView: View {
    @ObservedObject var dating: DatingViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        DatingGate(dating: dating, title: String(localized: "Анкета")) {
            // Анкета создана, но без фото: без него человека не узнать ни в чатах, ни в знакомствах.
            DatingProfileEditorView(dating: dating)
                .safeAreaInset(edge: .top) {
                    Label("Добавьте хотя бы одно фото — оно сразу станет вашим аватаром", systemImage: "camera.fill")
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
        }
        // Без анкеты в настройки не попасть — выход держим здесь, отдельной полосой над экраном.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button("Выйти") {
                    Task { await authViewModel.logout() }
                }
                .font(.app(.footnote))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
