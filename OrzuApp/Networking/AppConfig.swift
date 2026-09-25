import Foundation

enum AppConfig {
    // Backend опубликован через Caddy с HTTPS (см. README), поэтому работает и в Симуляторе,
    // и на физическом iPhone. Для локальной отладки без сервера можно временно вернуть
    // "http://localhost:3000" (Симулятор + SSH-туннель).
    static let apiBaseURL = URL(string: "https://adm.orzu.pro")!

    /// Куда ведёт «Обновить в App Store». Пока приложение не опубликовано, у него нет своей страницы —
    /// открывается сам App Store; после публикации сюда ставится адрес страницы (apps.apple.com/app/id…).
    static let appStoreURL = URL(string: "itms-apps://apps.apple.com")!

    static var wsBaseURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        return components.url!
    }
}
