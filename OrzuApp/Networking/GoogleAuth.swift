import GoogleSignIn
import UIKit

/// Получение Google ID-токена через Google Sign-In SDK. Проверяет токен и заводит аккаунт сервер (POST /auth/google).
enum GoogleAuth {
    /// Client ID iOS-клиента из Google Cloud Console (build setting GOOGLE_IOS_CLIENT_ID); пустой — кнопка входа скрыта.
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !value.isEmpty else { return nil }
        return value
    }

    static var isEnabled: Bool { clientID != nil }

    /// nil — пользователь закрыл окно Google, это не ошибка.
    @MainActor
    static func requestIDToken() async throws -> String? {
        guard let clientID, let presenter = topViewController() else {
            throw APIError.server("Вход через Google недоступен")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
        // Сессия Google приложению дальше не нужна — работаем со своими токенами, а в следующий раз можно выбрать другой аккаунт.
        defer { GIDSignIn.sharedInstance.signOut() }
        guard let idToken = result.user.idToken?.tokenString else { throw APIError.invalidResponse }
        return idToken
    }

    @MainActor
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
