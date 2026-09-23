import Foundation

struct Bot: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String
    let username: String
    let displayName: String
    let webhookUrl: String?
    /// Приходит только при создании — сервер хранит лишь хеш, показать токен повторно нельзя (только перевыпустить).
    let token: String?
}
