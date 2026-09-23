import Foundation

enum AppConfig {
    // Backend опубликован через Caddy с HTTPS (см. README), поэтому работает и в Симуляторе,
    // и на физическом iPhone. Для локальной отладки без сервера можно временно вернуть
    // "http://localhost:3000" (Симулятор + SSH-туннель).
    static let apiBaseURL = URL(string: "https://adm.orzu.pro")!

    static var wsBaseURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        return components.url!
    }
}
