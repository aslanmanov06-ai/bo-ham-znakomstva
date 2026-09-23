import Foundation

/// Уведомления, сеансы, отключение и удаление аккаунта, выгрузка данных, поддержка и документы.
extension APIClient {
    // MARK: - Уведомления

    func updateNotifications(_ settings: NotificationSettings) async throws -> AccountSettings {
        try await request(path: "/users/me/notifications", method: "PATCH", body: settings, authorized: true)
    }

    /// duration = nil — без звука навсегда.
    func muteChat(chatId: String, duration: TimeInterval?) async throws -> Date {
        let body = MuteChatBody(durationSec: duration.map { Int($0) })
        let response: MuteChatResponse = try await request(path: "/chats/\(chatId)/mute", method: "PUT", body: body, authorized: true)
        return response.mutedUntil
    }

    func unmuteChat(chatId: String) async throws {
        let _: EmptyResponse = try await request(path: "/chats/\(chatId)/mute", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Сеансы

    func fetchSessions() async throws -> [AccountSession] {
        try await request(path: "/auth/sessions", method: "GET", body: nil as String?, authorized: true)
    }

    func revokeSession(id: String) async throws {
        let _: EmptyResponse = try await request(path: "/auth/sessions/\(id)", method: "DELETE", body: nil as String?, authorized: true)
    }

    // MARK: - Отключение и удаление аккаунта

    func deactivateAccount() async throws -> AccountSettings {
        try await request(path: "/users/me/deactivate", method: "POST", body: nil as String?, authorized: true)
    }

    func reactivateAccount() async throws -> AccountSettings {
        try await request(path: "/users/me/reactivate", method: "POST", body: nil as String?, authorized: true)
    }

    /// password = nil — аккаунт из Google без пароля. После удаления токены на устройстве больше не нужны.
    func deleteAccount(password: String?) async throws {
        var body: [String: String] = [:]
        body["password"] = password
        let _: EmptyResponse = try await request(path: "/users/me", method: "DELETE", body: body, authorized: true)
        TokenStore.shared.clear()
    }

    // MARK: - Поддержка

    func fetchSupportTickets() async throws -> [SupportTicket] {
        try await request(path: "/support", method: "GET", body: nil as String?, authorized: true)
    }

    func createSupportTicket(category: SupportCategory, text: String) async throws -> SupportTicket {
        try await request(path: "/support", method: "POST", body: CreateSupportTicketBody(category: category, text: text), authorized: true)
    }

    // MARK: - Документы

    /// Без авторизации: документы открываются и до входа. Правила сообщества — fetchCommunityRules.
    func fetchPrivacyPolicy() async throws -> LegalDocument {
        try await request(path: "/legal/privacy", method: "GET", body: nil as String?, authorized: false)
    }

    func fetchTermsOfService() async throws -> LegalDocument {
        try await request(path: "/legal/terms", method: "GET", body: nil as String?, authorized: false)
    }
}

private struct MuteChatBody: Encodable {
    let durationSec: Int?
}

private struct MuteChatResponse: Decodable {
    let mutedUntil: Date
}

private struct CreateSupportTicketBody: Encodable {
    let category: SupportCategory
    let text: String
}
