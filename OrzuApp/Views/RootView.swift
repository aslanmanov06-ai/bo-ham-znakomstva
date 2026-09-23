import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var appearance = AppearanceSettings.shared

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
        .fullScreenCover(isPresented: isCallActive) {
            CallOverlayView()
        }
        .preferredColorScheme(appearance.theme.colorScheme)
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
        case dating, browse, chats, profile
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var push = PushManager.shared
    @ObservedObject private var safetyAlerts = SafetyAlertsViewModel.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var socket = WebSocketClient.shared
    @State private var selection = AppTab.dating
    /// Анкета — часть профиля: её правят и во вкладках знакомств, и в «Моём профиле», поэтому модель одна на все.
    @StateObject private var dating = DatingViewModel()
    /// «Соединение…» показываем не сразу: обычно сокет подключается за доли секунды, и плашка только мигнула бы.
    @State private var isConnectingTooLong = false

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

            ChatListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.chats)

            NavigationStack { MyProfileView(dating: dating) { authViewModel.updateCurrentUser($0) } }
                .tabItem { Label("Мой профиль", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        .tabBarMinimizesOnScroll()
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
        .task(id: push.pendingSosId) {
            guard let sosId = push.pendingSosId else { return }
            push.pendingSosId = nil
            await safetyAlerts.open(alertId: sosId)
        }
        // Тревога доверенного контакта важнее текущего экрана — показываем её поверх вкладок.
        .fullScreenCover(item: $safetyAlerts.incomingAlert) { alert in
            SosAlertView(alert: alert) { safetyAlerts.incomingAlert = nil }
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

/// Обязательный шаг после регистрации (и для тех, кто вошёл до этого правила): правила сообщества → анкета →
/// хотя бы одно фото. Когда фото добавлено, RootView сам покажет вкладки.
private struct ProfileOnboardingView: View {
    @ObservedObject var dating: DatingViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        DatingGate(dating: dating, title: "Анкета") {
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
