import SwiftUI

/// «Как это работает» — словарик приложения: короткое объяснение каждого слова, которое встречается в знакомствах.
struct HowItWorksView: View {
    private struct Entry: Identifiable {
        let systemImage: String
        let tint: Color
        let title: String
        let text: String

        var id: String { title }
    }

    private let entries: [Entry] = [
        Entry(systemImage: "heart", tint: .brand, title: String(localized: "Знакомства"),
              text: String(localized: "Лента тех, кто подходит вам и кому подходите вы. Подбирает приложение.")),
        Entry(systemImage: "magnifyingglass", tint: .brand, title: String(localized: "Поиск"),
              text: String(localized: "Все анкеты. Ищите сами по своему фильтру.")),
        Entry(systemImage: "shuffle", tint: .brand, title: String(localized: "Рулетка"),
              text: String(localized: "Случайный собеседник прямо сейчас — видео или переписка.")),
        Entry(systemImage: "heart.circle", tint: .champagne, title: String(localized: "Лайк и пара"),
              text: String(localized: "Лайк взаимный — вы пара, и открывается чат.")),
        Entry(systemImage: "paperplane", tint: .champagne, title: String(localized: "Написать"),
              text: String(localized: "Первое сообщение вместе с лайком. Ответят за сутки — вы пара.")),
        Entry(systemImage: "tray", tint: .champagne, title: String(localized: "Запрос на переписку"),
              text: String(localized: "Сообщение незнакомому человеку. Чат откроется, когда он ответит.")),
        Entry(systemImage: "checkmark.shield", tint: .champagne, title: String(localized: "Проверка селфи"),
              text: String(localized: "Модератор сверяет селфи с фото — до 24 часов. Потом значок «проверен».")),
        Entry(systemImage: "signpost.right", tint: .champagne, title: String(localized: "Путь к браку"),
              text: String(localized: "Общие шаги пары от знакомства до никаха. Ступень меняется, когда согласны оба.")),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Коротко о главном: что значат слова, которые встречаются в знакомствах.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                        if entry.id != entries.last?.id {
                            Divider().overlay(Color.appLine)
                        }
                    }
                }
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .appScreenBackground()
        .navigationTitle("Как это работает")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(entry.tint)
                .frame(width: 36, height: 36)
                .background(entry.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.app(.body, weight: .semibold))
                Text(entry.text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
