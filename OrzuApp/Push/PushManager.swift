import Foundation
import UIKit
import UserNotifications
import os

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
        await MainActor.run {
            self.pendingChatId = chatId
            self.pendingSosId = sosId
            self.pendingDating = dating
        }
    }
}
