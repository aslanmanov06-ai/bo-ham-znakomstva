import Foundation

/// Устройство, где выполнен вход. current — это самое устройство.
struct AccountSession: Decodable, Identifiable, Hashable {
    let id: String
    let deviceName: String?
    let createdAt: Date
    let lastUsedAt: Date
    let current: Bool
}

enum SupportCategory: String, Codable, CaseIterable, Identifiable {
    case account = "ACCOUNT"
    case bug = "BUG"
    case safety = "SAFETY"
    case appeal = "APPEAL"
    case idea = "IDEA"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Аккаунт и вход"
        case .bug: return "Ошибка в приложении"
        case .safety: return "Безопасность"
        case .appeal: return "Несогласие с решением"
        case .idea: return "Предложение"
        case .other: return "Другое"
        }
    }
}

/// Обращение в поддержку. Ответ модератора приходит push-уведомлением и появляется в reply.
struct SupportTicket: Decodable, Identifiable, Hashable {
    let id: String
    let category: SupportCategory
    let text: String
    let reply: String?
    let repliedAt: Date?
    let createdAt: Date
}

/// Политика конфиденциальности или пользовательское соглашение — тексты отдаёт сервер.
struct LegalDocument: Codable, Hashable {
    struct Section: Codable, Hashable {
        let title: String
        let paragraphs: [String]
    }

    let version: String
    let title: String
    let sections: [Section]
}

/// Документы из раздела «Помощь». Правила сообщества приходят в своём формате — см. LegalDocumentView.
enum LegalDocumentKind: String, Identifiable {
    case rules
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: return "Правила сообщества"
        case .privacy: return "Конфиденциальность"
        case .terms: return "Соглашение"
        }
    }

    var systemImage: String {
        switch self {
        case .rules: return "list.bullet.rectangle.fill"
        case .privacy: return "lock.fill"
        case .terms: return "doc.text.fill"
        }
    }
}
