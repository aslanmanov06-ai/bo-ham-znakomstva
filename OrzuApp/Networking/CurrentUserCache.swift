import Foundation

/// Профиль вошедшего пользователя на устройстве: с ним приложение открывает вкладки сразу и без интернета,
/// не дожидаясь /auth/me. Секретов тут нет (токены лежат в Keychain), поэтому хватает UserDefaults.
struct CurrentUserCache {
    private static let key = "com.orzuapp.messenger.currentUser"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> User? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        guard let user = try? ISO8601Coding.makeDecoder().decode(User.self, from: data) else {
            // Формат User поменялся в новой версии — старая копия бесполезна, профиль придёт с сервера.
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return user
    }

    func save(_ user: User?) {
        guard let user, let data = try? ISO8601Coding.makeEncoder().encode(user) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
