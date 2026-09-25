import Foundation
import Combine
import UIKit
import os

@MainActor
final class AuthViewModel: ObservableObject {
    /// Каждое изменение сразу пишется на устройство. nil — выход или истёкшая сессия: вместе с профилем
    /// стираются и все офлайн-данные этого пользователя.
    @Published var currentUser: User? {
        didSet {
            userCache.save(currentUser)
            if currentUser == nil { forgetOfflineData() }
        }
    }
    /// Токен есть, а сохранённого профиля нет (первый запуск после обновления): ждём /auth/me вместо экрана входа —
    /// и без сети тоже ждём, а не выкидываем человека из аккаунта.
    @Published private(set) var isRestoringSession = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Первый вход через Google: аккаунта ещё нет, показываем анкету.
    @Published var pendingGoogleRegistration: GoogleRegistration?

    var isAuthenticated: Bool { currentUser != nil }

    /// Сервер недоступен при живой сети: повторяем, пока ждём профиль на экране ожидания.
    private static let restoreRetryDelay: Duration = .seconds(10)

    private let userCache = CurrentUserCache()
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Auth")
    private var cancellables = Set<AnyCancellable>()
    private var restoreRetryTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.publisher(for: .sessionExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSessionExpired() }
            .store(in: &cancellables)
        // Имя и аватар могли смениться на другом устройстве, пока приложение было без сети или в фоне.
        NotificationCenter.default.publisher(for: .networkBecameAvailable)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard TokenStore.shared.accessToken != nil else { return }
                Task { await self?.refreshCurrentUser() }
            }
            .store(in: &cancellables)
        restoreSession()
    }

    /// Вошедший пользователь попадает во вкладки сразу, даже без интернета: профиль берём с устройства,
    /// а свежий запрашиваем в фоне.
    private func restoreSession() {
        guard TokenStore.shared.accessToken != nil else {
            // Без токенов сессии нет, а данные могли остаться от неё — не впускаем по ним во вкладки.
            currentUser = nil
            return
        }
        if let cachedUser = userCache.load() {
            didAuthenticate(cachedUser)
        } else {
            isRestoringSession = true
        }
        Task { await refreshCurrentUser() }
    }

    private func refreshCurrentUser() async {
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        do {
            let user = try await APIClient.shared.me()
            // Пока шёл запрос, человек мог выйти — не впускаем его обратно.
            guard TokenStore.shared.accessToken != nil else { return }
            isRestoringSession = false
            if currentUser == nil {
                didAuthenticate(user)
            } else {
                currentUser = user
            }
        } catch let error as APIError where error.isTransient {
            // Нет сети или сбой сервера — не повод выкидывать человека из аккаунта: токены и профиль остаются.
            // Без профиля ждём на экране ожидания; сеть появится — сработает .networkBecameAvailable.
            if isRestoringSession { scheduleRestoreRetry() }
        } catch {
            // Отозванную сессию APIClient закрывает сам через .sessionExpired.
            logger.error("Не удалось обновить профиль: \(error.localizedDescription, privacy: .public)")
            isRestoringSession = false
        }
    }

    private func scheduleRestoreRetry() {
        restoreRetryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restoreRetryDelay)
            guard !Task.isCancelled else { return }
            await self?.refreshCurrentUser()
        }
    }

    /// Ответы сервера, неотправленные сообщения, скачанные вложения и фильтры анкет — всё принадлежит вышедшему пользователю.
    private func forgetOfflineData() {
        APIClient.shared.clearResponseCache()
        DatingBrowseViewModel.forgetFilters()
        MessageOutbox.shared.removeAll()
        Task { await AttachmentLoader.shared.removeAll() }
    }

    // Шаги регистрации бросают ошибки, а не пишут их в errorMessage: экран формы и экран кода показывают их у себя
    // (занятую почту — под полем почты, неверный код — под ячейками).

    func requestRegistrationCode(email: String, username: String) async throws {
        try await APIClient.shared.requestRegistrationCode(email: email, username: username)
    }

    func register(username: String, displayName: String, password: String, email: String, phone: String, code: String) async throws {
        let response = try await APIClient.shared.register(
            username: username, displayName: displayName, password: password, email: email, phone: phone, code: code
        )
        didAuthenticate(response.user)
    }

    func login(username: String, password: String) async {
        await run {
            let response = try await APIClient.shared.login(username: username, password: password)
            self.didAuthenticate(response.user)
        }
    }

    func signInWithGoogle() async {
        await run {
            guard let idToken = try await GoogleAuth.requestIDToken() else { return }
            switch try await APIClient.shared.googleSignIn(idToken: idToken) {
            case .authenticated(let response):
                self.didAuthenticate(response.user)
            case .registrationRequired(let registration):
                self.pendingGoogleRegistration = registration
            }
        }
    }

    /// `email` — только если Google почту не передал; иначе код уходит на почту из Google.
    func requestGoogleRegistrationCode(_ registration: GoogleRegistration, username: String, email: String?) async throws {
        try await APIClient.shared.requestGoogleRegistrationCode(
            registrationToken: registration.registrationToken, username: username, email: email
        )
    }

    func completeGoogleRegistration(
        _ registration: GoogleRegistration, username: String, displayName: String, email: String?, phone: String, code: String
    ) async throws {
        let response = try await APIClient.shared.completeGoogleRegistration(
            registrationToken: registration.registrationToken, username: username, displayName: displayName,
            email: email, phone: phone, code: code
        )
        pendingGoogleRegistration = nil
        didAuthenticate(response.user)
    }

    func logout() async {
        isRestoringSession = false
        restoreRetryTask?.cancel()
        await CallManager.shared.userWillLogOut()
        WebSocketClient.shared.disconnect()
        await PushManager.shared.userWillLogOut()
        await APIClient.shared.logout()
        currentUser = nil
    }

    /// Сессии гасятся на сервере везде; push на это устройство тоже больше не придут (сервер удаляет его токены).
    func logoutEverywhere() async {
        await CallManager.shared.userWillLogOut()
        WebSocketClient.shared.disconnect()
        do {
            try await APIClient.shared.logoutEverywhere()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        currentUser = nil
    }

    /// Бросает ошибку, чтобы экран удаления показал её рядом с полем пароля. Push-токены сервер удаляет вместе с аккаунтом.
    func deleteAccount(password: String?) async throws {
        try await APIClient.shared.deleteAccount(password: password)
        await CallManager.shared.userWillLogOut()
        WebSocketClient.shared.disconnect()
        PushManager.shared.accountWasDeleted()
        currentUser = nil
    }

    /// Новое имя или аватар из настроек.
    func updateCurrentUser(_ user: User) {
        currentUser = user
    }

    /// Токены уже очищены APIClient, поэтому отвязка устройства (нужен валидный access token) здесь невозможна.
    private func handleSessionExpired() {
        isRestoringSession = false
        guard currentUser != nil else { return }
        WebSocketClient.shared.disconnect()
        currentUser = nil
        errorMessage = APIError.unauthorized.errorDescription
    }

    private func didAuthenticate(_ user: User) {
        currentUser = user
        WebSocketClient.shared.connect()
        PushManager.shared.userDidLogIn()
        CallManager.shared.userDidLogIn()
        MessageOutbox.shared.flush()
        Task { await E2EKeyStore.shared.registerWithServer(userId: user.id) }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
