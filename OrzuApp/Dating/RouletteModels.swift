import Foundation

// Рулетка: случайный собеседник по видео или в переписке. Протокол — backend docs/roulette.md.
// До взаимного «Нравится» о собеседнике известны только пол, возраст, город и значок «проверен».

enum RouletteMode: String, Codable, Hashable {
    case text = "TEXT"
    case video = "VIDEO"
}

/// Почему режим недоступен. Незнакомый код (сервер новее приложения) — просто «недоступно».
enum RouletteIssue: String, Decodable, Hashable {
    case disabled = "DISABLED"
    case profileRequired = "PROFILE_REQUIRED"
    case deactivated = "DEACTIVATED"
    case inCouple = "IN_COUPLE"
    case restricted = "RESTRICTED"
    case rouletteBanned = "ROULETTE_BANNED"
    case notVerified = "NOT_VERIFIED"
    case unknown

    init(from decoder: Decoder) throws {
        self = RouletteIssue(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    var message: String {
        switch self {
        case .disabled: String(localized: "Рулетка временно недоступна")
        case .profileRequired: String(localized: "Сначала заполните анкету: пол, дату рождения, город и фото")
        case .deactivated: String(localized: "Аккаунт отключён — включите его в настройках")
        case .inCouple: String(localized: "Вы отметили, что нашли пару, — рулетка закрыта")
        case .restricted: String(localized: "Анкета ограничена модератором — рулетка недоступна")
        case .rouletteBanned: String(localized: "Рулетка закрыта для вас из-за жалоб")
        case .notVerified: String(localized: "Видео — только для анкет с подтверждённым селфи")
        case .unknown: String(localized: "Рулетка сейчас недоступна")
        }
    }
}

/// GET /roulette/status — экран выбора режима.
struct RouletteStatus: Decodable, Hashable {
    struct Availability: Decodable, Hashable {
        let available: Bool
        let reason: RouletteIssue?
    }

    struct Modes: Decodable, Hashable {
        let text: Availability
        let video: Availability

        private enum CodingKeys: String, CodingKey {
            case text = "TEXT"
            case video = "VIDEO"
        }
    }

    struct Search: Decodable, Hashable {
        let lookingFor: String
        let ageMin: Int
        let ageMax: Int
        let cityCode: String
    }

    struct Online: Decodable, Hashable {
        let text: Int
        let video: Int

        private enum CodingKeys: String, CodingKey {
            case text = "TEXT"
            case video = "VIDEO"
        }

        var total: Int { text + video }

        func count(of mode: RouletteMode) -> Int {
            mode == .video ? video : text
        }
    }

    /// Часы «вечера рулетки» по местному времени: [from, to).
    struct Evening: Decodable, Hashable {
        let from: Int
        let to: Int

        /// «20:00–23:00».
        var range: String {
            String(format: "%02d:00–%02d:00", from, to % 24)
        }
    }

    let modes: Modes
    let bannedUntil: Date?
    let search: Search?
    let cityWaitSeconds: Int
    /// Сколько людей сейчас ищут и разговаривают. nil — сервер старее приложения.
    let online: Online?
    let evening: Evening?
    var reminder: Bool?

    func availability(of mode: RouletteMode) -> Availability {
        mode == .video ? modes.video : modes.text
    }
}

/// Собеседник до взаимной симпатии.
struct RoulettePeer: Decodable, Hashable {
    let gender: String
    let age: Int
    let cityCode: String
    let verified: Bool

    var isFemale: Bool { gender == "FEMALE" }

    /// «Девушка, 24» — так собеседник подписан в разговоре.
    var title: String {
        isFemale ? String(localized: "Девушка, \(age)") : String(localized: "Парень, \(age)")
    }
}

/// Сообщение переписки рулетки, как его присылает сервер.
struct RouletteWireMessage: Decodable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
}

struct RouletteChatMessage: Identifiable, Hashable {
    /// До подтверждения сервером — clientId, потом — id сообщения.
    var id: String
    let text: String
    let isMine: Bool
    var createdAt: Date
    var isPending: Bool
}

/// Причины жалобы из рулетки — как в макете. Коды — общие с обычными жалобами (ReportCategory).
enum RouletteReportReason: CaseIterable, Identifiable {
    case indecent, harassment, spam, underage, other

    var id: Self { self }

    var category: ReportCategory {
        switch self {
        case .indecent: .inappropriateContent
        case .harassment: .harassment
        case .spam: .spam
        case .underage: .underage
        case .other: .other
        }
    }

    var title: String {
        switch self {
        case .indecent: String(localized: "Непристойное поведение")
        case .harassment: String(localized: "Оскорбления или угрозы")
        case .spam: String(localized: "Спам, реклама, мошенничество")
        case .underage: String(localized: "Похоже на несовершеннолетнего")
        case .other: String(localized: "Другое")
        }
    }
}
