import Foundation

/// Backend (Prisma) отдаёт даты с миллисекундами (`.withFractionalSeconds`), а стандартная стратегия
/// `.iso8601` в Foundation их не парсит — отсюда общий форматтер для энкодера и декодера везде в приложении.
enum ISO8601Coding {
    static let formatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let formatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatterWithFraction.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatterWithFraction.date(from: string) ?? formatterNoFraction.date(from: string)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Некорректная дата: \(string)")
            }
            return date
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }
}
