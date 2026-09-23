import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    /// nil у старых ответов сервера, где поля ещё не было.
    var isBot: Bool? = nil
    /// Есть только у собеседников по личным чатам: в группах и в поиске сервер присутствие не отдаёт.
    var presence: Presence? = nil
}
