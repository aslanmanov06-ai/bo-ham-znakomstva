import Combine
import Foundation

/// Недописанные сообщения по чатам: переживают выход из чата и перезапуск приложения, видны в списке как «Черновик:».
/// Хранятся только на этом устройстве и стираются при выходе из аккаунта.
@MainActor
final class ChatDraftStore: ObservableObject {
    static let shared = ChatDraftStore()

    @Published private(set) var drafts: [String: String]

    private let defaults: UserDefaults
    private static let key = "chatDrafts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drafts = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func draft(chatId: String) -> String {
        drafts[chatId] ?? ""
    }

    /// Пробелы и переводы строк черновиком не считаются — такой «черновик» убираем.
    func setDraft(_ text: String, chatId: String) {
        let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard (isBlank ? nil : text) != drafts[chatId] else { return }
        drafts[chatId] = isBlank ? nil : text
        defaults.set(drafts, forKey: Self.key)
    }

    func removeAll() {
        drafts = [:]
        defaults.removeObject(forKey: Self.key)
    }
}
