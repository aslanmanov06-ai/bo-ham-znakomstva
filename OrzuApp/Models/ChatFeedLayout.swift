import Foundation

/// Как строка ленты встаёт в переписку (макет «Лента: даты, группы, новые, «печатает»»): над первой за день — дата,
/// подряд идущие сообщения одного автора за несколько минут собираются в группу с узким зазором,
/// и только у первого в группе скругление со стороны автора большое.
struct ChatRowLayout: Equatable {
    /// «Сегодня», «Вчера», «14 сентября» — над первым сообщением дня; nil — дата та же, что выше.
    var dayLabel: String?
    /// Продолжение группы: зазор 2 pt вместо 8 и малое скругление сверху со стороны автора.
    var continuesGroup = false

    static let single = ChatRowLayout()
}

enum ChatFeedLayout {
    /// Сообщения дальше этого промежутка друг от друга — уже отдельные группы, даже от одного автора.
    static let groupWindow: TimeInterval = 5 * 60

    /// Раскладка по rowId. Служебные строки (isSystem) группу разрывают и сами в группы не входят.
    static func layout(
        _ messages: [Message],
        isSystem: (Message) -> Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String: ChatRowLayout] {
        var result: [String: ChatRowLayout] = [:]
        var previous: Message?
        for message in messages {
            var row = ChatRowLayout()
            let sameDay = previous.map { calendar.isDate($0.createdAt, inSameDayAs: message.createdAt) } ?? false
            if !sameDay {
                row.dayLabel = dayLabel(for: message.createdAt, now: now, calendar: calendar)
            }
            if let previous, sameDay, !isSystem(previous), !isSystem(message),
               previous.senderId == message.senderId,
               message.createdAt.timeIntervalSince(previous.createdAt) < groupWindow {
                row.continuesGroup = true
            }
            result[message.rowId] = row
            previous = message
        }
        return result
    }

    static func dayLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Сегодня") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Вчера")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMMM" : "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

