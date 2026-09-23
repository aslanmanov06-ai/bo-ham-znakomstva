import Foundation

/// «В сети» / «был(а) недавно» собеседника. Приходит внутри участников чата (GET /chats, GET /chats/:id)
/// и обновляется событием `presence`, когда у человека открылось первое или закрылось последнее соединение.
struct Presence: Codable, Hashable {
    let online: Bool
    /// Точное время последнего захода — только если человек не скрыл его в настройках приватности.
    var lastSeenAt: Date? = nil
    let lastSeen: LastSeen

    enum LastSeen: String, Codable, Hashable {
        case online = "ONLINE"
        case recently = "RECENTLY"
        case withinWeek = "WITHIN_WEEK"
        case withinMonth = "WITHIN_MONTH"
        case longAgo = "LONG_AGO"
    }

    /// Подпись под именем. Точное время показываем, только когда сервер его отдал, — иначе приблизительную давность.
    func subtitle(now: Date = Date()) -> String {
        if online { return "в сети" }
        if let lastSeenAt { return "был(а) \(Self.exactLabel(for: lastSeenAt, now: now))" }
        switch lastSeen {
        case .online: return "в сети"
        case .recently: return "был(а) недавно"
        case .withinWeek: return "был(а) на этой неделе"
        case .withinMonth: return "был(а) в этом месяце"
        case .longAgo: return "был(а) давно"
        }
    }

    private static func exactLabel(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "в \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) {
            return "вчера в \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
