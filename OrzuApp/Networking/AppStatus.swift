import Combine
import Foundation
import UIKit

/// Что сервер сообщает о приложении целиком (GET /app/config, без входа).
struct AppRuntimeConfig: Decodable, Equatable {
    let maintenance: Bool
    let maintenanceMessage: String
    let registrationOpen: Bool
    let minIosVersion: String
}

/// Блокировка аккаунта из отказа ACCOUNT_BANNED. appealToken — пропуск на обжалование без входа, живёт час.
struct BanNotice: Decodable, Equatable {
    /// nil — бессрочно.
    let bannedUntil: Date?
    let permanent: Bool
    let reason: String?
    let appealToken: String?
}

extension Notification.Name {
    /// Сервер ответил 503 MAINTENANCE; object — текст администратора (String?).
    static let maintenanceDetected = Notification.Name("com.orzuapp.messenger.maintenanceDetected")
    /// Сервер ответил 403 ACCOUNT_BANNED; object — BanNotice.
    static let accountBanned = Notification.Name("com.orzuapp.messenger.accountBanned")
}

/// Версия приложения против минимальной с сервера: «1.10» новее «1.9», недостающие части — нули («1.2» = «1.2.0»).
enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func isOlder(_ version: String, than minimum: String) -> Bool {
        let lhs = parts(version)
        let rhs = parts(minimum)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// Состояние приложения целиком, которое закрывает все экраны: обязательное обновление, блокировка аккаунта,
/// режим обслуживания. Узнаёт о них из конфига при запуске и возврате из фона и из отказов любых запросов.
@MainActor
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    /// Пока идёт обслуживание, сами перепроверяем сервер — человеку не нужно ничего нажимать.
    private static let maintenancePollInterval: Duration = .seconds(30)
    static let defaultMaintenanceMessage = "Обновляем Бо Хам. Скоро вернёмся — спасибо, что подождёте."

    @Published private(set) var config: AppRuntimeConfig?
    @Published private(set) var isUnderMaintenance = false
    @Published private(set) var maintenanceMessage = AppStatus.defaultMaintenanceMessage
    @Published private(set) var registrationClosed = false
    @Published var ban: BanNotice?

    private var pollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var updateRequired: Bool {
        guard let minimum = config?.minIosVersion else { return false }
        return AppVersion.isOlder(AppVersion.current, than: minimum)
    }

    private init() {
        NotificationCenter.default.publisher(for: .maintenanceDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.enterMaintenance(message: notification.object as? String) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accountBanned)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.ban = notification.object as? BanNotice }
            .store(in: &cancellables)
        // Минимальную версию и обслуживание могли включить, пока приложение было свёрнуто.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    /// Без сети конфиг не придёт — остаётся прежний: офлайн приложение работает с сохранёнными данными.
    func refresh() async {
        guard let fresh = try? await APIClient.shared.fetchAppConfig() else { return }
        apply(fresh)
    }

    /// Сервер отказал в регистрации — экран регистрации покажет, что она закрыта, не дожидаясь конфига.
    func markRegistrationClosed() {
        registrationClosed = true
    }

    /// «Выйти из аккаунта» на экране блокировки. Токены чистит AuthViewModel.
    func dismissBan() {
        ban = nil
    }

    private func apply(_ fresh: AppRuntimeConfig) {
        config = fresh
        registrationClosed = !fresh.registrationOpen
        maintenanceMessage = fresh.maintenanceMessage
        if fresh.maintenance {
            enterMaintenance(message: fresh.maintenanceMessage)
        } else {
            leaveMaintenance()
        }
    }

    private func enterMaintenance(message: String?) {
        if let message, !message.isEmpty { maintenanceMessage = message }
        isUnderMaintenance = true
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.maintenancePollInterval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func leaveMaintenance() {
        pollTask?.cancel()
        pollTask = nil
        guard isUnderMaintenance else { return }
        isUnderMaintenance = false
        // Для экранов и очереди отправки сервер снова доступен — то же, что появление сети:
        // очередь отправит накопленные сообщения, чаты перечитают пропущенное.
        NotificationCenter.default.post(name: .networkBecameAvailable, object: nil)
    }
}
