import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AccountSettings?
    @Published var blockedUsers: [User] = []
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isBusy = false

    /// Имя показывается и в других экранах — сообщаем AuthViewModel о новом профиле.
    private let onProfileChanged: (User) -> Void

    init(onProfileChanged: @escaping (User) -> Void) {
        self.onProfileChanged = onProfileChanged
    }

    func load() async {
        await run { self.settings = try await APIClient.shared.fetchSettings() }
    }

    func saveDisplayName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != settings?.displayName else { return }
        await apply { try await APIClient.shared.updateProfile(displayName: trimmed) }
    }

    /// true — сохранено: экран смены username можно закрыть.
    func saveUsername(_ username: String) async -> Bool {
        await apply { try await APIClient.shared.updateUsername(username) }
        return errorMessage == nil
    }

    func updatePrivacy(_ update: PrivacyUpdate) async {
        await apply { try await APIClient.shared.updatePrivacy(update) }
    }

    func loadBlocked() async {
        await run { self.blockedUsers = try await APIClient.shared.fetchBlockedUsers() }
    }

    func unblock(_ user: User) async {
        await run {
            try await APIClient.shared.unblockUser(id: user.id)
            self.blockedUsers.removeAll { $0.id == user.id }
        }
    }

    func requestEmailCode(_ email: String) async -> Bool {
        var sent = false
        await run {
            try await APIClient.shared.requestEmailVerification(email: email.trimmingCharacters(in: .whitespaces))
            self.infoMessage = "Код отправлен на \(email). Проверьте и папку «Спам»."
            sent = true
        }
        return sent
    }

    func verifyEmail(code: String) async -> Bool {
        await apply { try await APIClient.shared.verifyEmail(code: code) }
        return errorMessage == nil
    }

    func removeEmail() async {
        await apply { try await APIClient.shared.removeEmail() }
    }

    func updateNotifications(_ notifications: NotificationSettings) async {
        await apply { try await APIClient.shared.updateNotifications(notifications) }
    }

    /// Отключённый аккаунт скрыт из ленты и поиска, но вход, чаты и пары остаются.
    func setDeactivated(_ deactivated: Bool) async {
        await apply {
            deactivated ? try await APIClient.shared.deactivateAccount() : try await APIClient.shared.reactivateAccount()
        }
    }

    /// current == nil — пароль задаётся впервые (аккаунт создан через Google).
    func changePassword(current: String?, new: String) async -> Bool {
        var changed = false
        await run {
            try await APIClient.shared.changePassword(current: current, new: new)
            self.infoMessage = "Пароль сохранён. На других устройствах нужно войти заново."
            changed = true
            self.settings = try await APIClient.shared.fetchSettings()
        }
        return changed
    }

    /// Выполняет запрос, который возвращает свежие настройки, и обновляет профиль в остальном приложении.
    private func apply(_ operation: @escaping () async throws -> AccountSettings) async {
        await run {
            let updated = try await operation()
            self.settings = updated
            self.onProfileChanged(updated.user)
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
