import Foundation
import UIKit
import UserNotifications
import os

/// Ссылка, открывшая приложение: https://adm.orzu.pro/u/<username> — человек, /c/<username> — канал.
/// Схема boham:// — то же самое без веб-домена (для проверки и ссылок из других приложений).
enum DeepLink: Equatable {
    case user(username: String)
    case channel(username: String)

    static let scheme = "boham"

    static func parse(_ url: URL) -> DeepLink? {
        let parts: [String]
        switch url.scheme?.lowercased() {
        case "https", "http":
            guard url.host?.lowercased() == AppConfig.apiBaseURL.host?.lowercased() else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        case scheme:
            // boham://u/alisa: «u» — это host, имя — путь.
            parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        default:
            return nil
        }
        guard parts.count == 2 else { return nil }
        let username = UsernameRules.normalized(parts[1]).lowercased()
        guard UsernameRules.isValid(username) else { return nil }
        switch parts[0].lowercased() {
        case "u": return .user(username: username)
        case "c": return .channel(username: username)
        default: return nil
        }
    }

    /// Ссылка «Поделиться» — веб-адрес: откроет приложение, если оно стоит, иначе страницу на сайте.
    var url: URL {
        switch self {
        case .user(let username): return AppConfig.apiBaseURL.appendingPathComponent("u").appendingPathComponent(username)
        case .channel(let username): return AppConfig.apiBaseURL.appendingPathComponent("c").appendingPathComponent(username)
        }
    }
}

@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    /// Чат, который нужно открыть после тапа по уведомлению.
    @Published var pendingChatId: String?
    /// Тап по уведомлению знакомств без чата (первое сообщение, встреча, «Путь к браку») — открыть вкладку.
    @Published var pendingDating = false
    /// «Написать» из анкеты: открыть вкладку «Чаты» и переписку с этим человеком (или запрос, если чата нет).
    @Published var pendingConversation: User?

    /// «Написать» из анкеты открывает мессенджер: переписку, а если чата ещё нет — первое сообщение запросом.
    func openConversation(with profile: DatingProfilePublic) {
        pendingConversation = profile.messengerUser
    }
    /// Тревога доверенного контакта: её нужно открыть сразу, из любой вкладки.
    @Published var pendingSosId: String?
    /// Модератор попросил новое селфи — открыть «Мой профиль» и экран проверки.
    @Published var pendingSelfieRequest = false
    /// Push «Вас лайкнули» — открыть знакомства и список лайкнувших.
    @Published var pendingLikedMe = false
    /// Push «Вечер рулетки» — открыть вкладку «Рулетка».
    @Published var pendingRoulette = false
    /// Открыли ссылку на человека или канал. Ждёт, пока пользователь войдёт, — потом её разберут вкладки.
    @Published var pendingDeepLink: DeepLink?

    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Push")
    private var deviceToken: String?
    private var isLoggedIn = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userDidLogIn() {
        isLoggedIn = true
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else { return }
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                logger.error("Не удалось запросить разрешение: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Вызывать до очистки токенов авторизации — DELETE /devices требует валидный access token.
    func userWillLogOut() async {
        isLoggedIn = false
        guard let deviceToken else { return }
        do {
            try await APIClient.shared.unregisterDevice(token: deviceToken)
        } catch {
            logger.error("Не удалось отвязать устройство: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Аккаунт удалён — его токены сервер уже стёр, отвязывать устройство некому.
    func accountWasDeleted() {
        isLoggedIn = false
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        guard isLoggedIn else { return }
        Task {
            do {
                try await APIClient.shared.registerDevice(token: token)
            } catch {
                logger.error("Не удалось зарегистрировать устройство: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func didFailToRegister(error: Error) {
        // На Симуляторе без поддержки remote push и без paid Apple Developer-аккаунта сюда попадаем штатно.
        logger.error("Регистрация в APNs не удалась: \(error.localizedDescription, privacy: .public)")
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    /// Сервер шлёт push всегда. Флаг live — событие приложение получает по WebSocket и показывает само:
    /// пока сокет подключён, баннер поверх него лишний. Без сокета (переподключается) баннер нужен — иначе о событии не узнать.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isLive = notification.request.content.userInfo["live"] as? Bool == true
        let socketReady = await MainActor.run { WebSocketClient.shared.isReady }
        return isLive && socketReady ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        // В уведомлении о паре chatId бывает пустой строкой — чат ещё не создан, открывать нечего.
        let chatId = (info["chatId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let sosId = info["sosId"] as? String
        // Первое сообщение, встреча и «Путь к браку» ведут во вкладку «Знакомства», а не в чат.
        let dating = chatId == nil && (info["introId"] != nil || info["meetingId"] != nil || info["matchId"] != nil)
        let selfieRequest = info["moderation"] as? String == "dating.selfieRequested"
        let likedMe = info["type"] as? String == "dating.liked"
        let roulette = info["type"] as? String == "roulette.reminder"
        await MainActor.run {
            self.pendingChatId = chatId
            self.pendingSosId = sosId
            self.pendingDating = dating || likedMe
            if selfieRequest { self.pendingSelfieRequest = true }
            if likedMe { self.pendingLikedMe = true }
            if roulette { self.pendingRoulette = true }
        }
    }
}
