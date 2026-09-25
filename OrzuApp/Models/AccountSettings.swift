import Foundation

/// Кто может писать / добавлять в группы. «Знакомые» — те, с кем уже есть личный чат.
enum PrivacyLevel: String, Codable, CaseIterable, Identifiable {
    case everyone = "EVERYONE"
    case contacts = "CONTACTS"
    case nobody = "NOBODY"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: return "Все"
        case .contacts: return "Знакомые"
        case .nobody: return "Никто"
        }
    }
}

struct AccountSettings: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let email: String?
    let messagePrivacy: PrivacyLevel
    let groupInvitePrivacy: PrivacyLevel
    /// false — в мессенджере не находят вовсе, даже по точному @username.
    let messengerSearchByUsername: Bool
    /// false — анкету не найти поиском по @username в знакомствах.
    let datingSearchByUsername: Bool
    /// false — на сервере не настроена отправка писем, привязать почту сейчас нельзя.
    let mailEnabled: Bool
    /// false — аккаунт создан через Google и пароль ещё не задан: вход только через Google.
    let hasPassword: Bool
    let googleLinked: Bool
    /// Аккаунт временно отключён: анкета скрыта из ленты и поиска, новые чаты с ним не начать.
    let deactivated: Bool
    let notifications: NotificationSettings

    var user: User {
        User(id: id, username: username, displayName: displayName, avatarUrl: avatarUrl)
    }
}

/// Какие push присылать. SOS, решения модераторов и ответы поддержки приходят всегда — их здесь нет.
struct NotificationSettings: Codable, Equatable {
    var messages: Bool
    var matches: Bool
    var intros: Bool
    var meetings: Bool
    /// false — на экране блокировки только «Бо Хам · Новое сообщение», без имени и текста.
    var preview: Bool
    /// Рассылки команды Бо Хам из админки: новые функции и объявления.
    var news: Bool
}
