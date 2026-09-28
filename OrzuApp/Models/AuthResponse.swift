import Foundation

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
}

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

/// Через кого пришёл первый вход: от этого зависят адреса регистрации (/auth/google/… или /auth/apple/…)
/// и подписи в анкете. Ответы у обоих одинаковые, поэтому типы общие.
enum SocialAuthProvider: String {
    case google, apple

    var title: String {
        switch self {
        case .google: return "Google"
        case .apple: return "Apple"
        }
    }
}

/// Ответ POST /auth/google и /auth/apple: либо вход выполнен, либо аккаунта ещё нет и нужно заполнить анкету.
enum GoogleSignInResponse: Decodable {
    case authenticated(AuthResponse)
    case registrationRequired(GoogleRegistration)

    private enum CodingKeys: String, CodingKey { case status }

    init(from decoder: Decoder) throws {
        let status = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .status)
        switch status {
        case "authenticated": self = .authenticated(try AuthResponse(from: decoder))
        case "registration_required": self = .registrationRequired(try GoogleRegistration(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.status], debugDescription: "Неизвестный статус \(status)"))
        }
    }
}

/// «Пропуск» на регистрацию после первого входа через Google или Apple (живёт 30 минут) и данные для анкеты.
struct GoogleRegistration: Decodable, Identifiable {
    struct Profile: Decodable {
        let email: String?
        let displayName: String?
    }

    let registrationToken: String
    let profile: Profile
    /// Сервер его не присылает — проставляет тот, кто запрашивал вход.
    var provider: SocialAuthProvider = .google

    private enum CodingKeys: String, CodingKey {
        case registrationToken, profile
    }

    var id: String { registrationToken }

    /// Подсказка из почты: «Ivan.Petrov@gmail.com» → «ivanpetrov». Пустая, если из адреса не выходит допустимый username.
    var suggestedUsername: String {
        guard let local = profile.email?.split(separator: "@").first?.lowercased() else { return "" }
        let candidate = String(local.filter(UsernameRules.isAllowedCharacter).prefix(UsernameRules.length.upperBound))
        return UsernameRules.length.contains(candidate.count) ? candidate : ""
    }
}

/// Те же правила, что у сервера (src/users/username.ts): 3–32 символа, латиница, цифры и «_».
enum UsernameRules {
    static let length = 3...32

    static func isAllowedCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    static func isValid(_ username: String) -> Bool {
        length.contains(username.count) && username.allSatisfy(isAllowedCharacter)
    }

    /// «@alisa » → «alisa»: так username пишут в тексте и копируют из профиля.
    static func normalized(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        return value
    }
}

/// Телефон в анкете регистрации — как на сервере (src/users/phone.ts): E.164, «+», код страны и до 15 цифр.
enum PhoneRules {
    /// Рынок — Таджикистан: поле открывается с кодом страны, человеку остаётся ввести номер.
    static let defaultPrefix = "+992 "
    private static let digitCount = 8...15

    /// «+992 (90) 123-45-67» → «+992901234567»: пробелы, скобки и дефисы убираем, «+» ставим сами.
    static func normalized(_ input: String) -> String {
        "+" + input.filter { $0.isASCII && $0.isNumber }
    }

    static func isValid(_ input: String) -> Bool {
        let digits = normalized(input).dropFirst()
        return digitCount.contains(digits.count) && digits.first != "0"
    }
}
