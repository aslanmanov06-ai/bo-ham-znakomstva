import XCTest
@testable import OrzuApp

/// Лента чата: даты над днями, группы сообщений одного автора, разделитель «Новые сообщения» (макеты «Мессенджер — доработка»).
final class MessengerFeedTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dushanbe")!
        return calendar
    }()

    /// 2 октября 2026, 12:00 по Душанбе.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!

    private func message(_ id: String, _ sender: String, minutesAgo: Double, system: Bool = false) -> Message {
        Message(id: id, chatId: "c", senderId: sender, text: id, createdAt: now.addingTimeInterval(-minutesAgo * 60),
                systemEvent: system ? Message.screenshotEvent : nil)
    }

    private func layout(_ messages: [Message]) -> [String: ChatRowLayout] {
        ChatFeedLayout.layout(messages, isSystem: { $0.systemEvent != nil }, now: now, calendar: calendar)
    }

    func testDayLabelOnlyOverFirstMessageOfEachDay() {
        let rows = layout([
            message("y1", "a", minutesAgo: 24 * 60), message("y2", "b", minutesAgo: 24 * 60 - 1),
            message("t1", "a", minutesAgo: 30), message("t2", "a", minutesAgo: 29),
        ])
        XCTAssertEqual(rows["y1"]?.dayLabel, "Вчера")
        XCTAssertNil(rows["y2"]?.dayLabel)
        XCTAssertEqual(rows["t1"]?.dayLabel, "Сегодня")
        XCTAssertNil(rows["t2"]?.dayLabel)
    }

    func testOlderDaysUseDateAndYearWhenNotThisYear() {
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 19))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 10))!
        XCTAssertEqual(ChatFeedLayout.dayLabel(for: september, now: now, calendar: calendar), "14 сентября")
        XCTAssertEqual(ChatFeedLayout.dayLabel(for: lastYear, now: now, calendar: calendar), "31 декабря 2025")
    }

    func testSameAuthorWithinFiveMinutesContinuesGroup() {
        let rows = layout([
            message("1", "a", minutesAgo: 10), message("2", "a", minutesAgo: 9), message("3", "b", minutesAgo: 8),
            message("4", "b", minutesAgo: 1),
        ])
        XCTAssertEqual(rows["1"]?.continuesGroup, false)
        XCTAssertEqual(rows["2"]?.continuesGroup, true)
        // Другой автор — новая группа.
        XCTAssertEqual(rows["3"]?.continuesGroup, false)
        // Тот же автор, но через 7 минут — тоже новая группа.
        XCTAssertEqual(rows["4"]?.continuesGroup, false)
    }

    func testSystemRowBreaksGroup() {
        let rows = layout([message("1", "a", minutesAgo: 3), message("s", "a", minutesAgo: 2, system: true), message("2", "a", minutesAgo: 1)])
        XCTAssertEqual(rows["s"]?.continuesGroup, false)
        XCTAssertEqual(rows["2"]?.continuesGroup, false)
    }

    func testNewMessagesPlural() {
        XCTAssertEqual(RussianPlural.newMessages(1), "1 новое сообщение")
        XCTAssertEqual(RussianPlural.newMessages(3), "3 новых сообщения")
        XCTAssertEqual(RussianPlural.newMessages(5), "5 новых сообщений")
        XCTAssertEqual(RussianPlural.newMessages(11), "11 новых сообщений")
        XCTAssertEqual(RussianPlural.newMessages(21), "21 новое сообщение")
        XCTAssertEqual(RussianPlural.newMessages(112), "112 новых сообщений")
    }

    func testLinksAndPhonesBecomeTappableButAppSchemesDoNot() {
        let text = "Маршрут: https://visittajikistan.tj/iskanderkul, звоните +992 93 555 12 34"
        let attributed = LinkifiedText.attributed(text, linkColor: .white)
        let links = attributed.runs.compactMap(\.link)
        XCTAssertTrue(links.contains(URL(string: "https://visittajikistan.tj/iskanderkul")!))
        XCTAssertTrue(links.contains { $0.scheme == "tel" && $0.absoluteString.hasSuffix("992935551234") })
    }

    func testVoiceWaveformIsStablePerAttachment() {
        let first = VoiceMessageView.barHeights(seed: "att-1", count: 26)
        XCTAssertEqual(first, VoiceMessageView.barHeights(seed: "att-1", count: 26))
        XCTAssertNotEqual(first, VoiceMessageView.barHeights(seed: "att-2", count: 26))
        XCTAssertTrue(first.allSatisfy { (6...24).contains($0) })
    }

    func testTypingDotsTakeTurns() {
        // В начале цикла первая точка уже поднимается, третья ещё лежит.
        XCTAssertGreaterThan(TypingDots.phase(time: 0.2, index: 0), 0)
        XCTAssertEqual(TypingDots.phase(time: 0.2, index: 2), 0)
        // Вторые 40 % цикла все точки лежат.
        XCTAssertEqual(TypingDots.phase(time: 1.15, index: 0), 0)
    }

    @MainActor
    func testDraftsSurviveAndBlankDraftIsRemoved() {
        let defaults = UserDefaults(suiteName: "drafts-test-\(UUID().uuidString)")!
        let store = ChatDraftStore(defaults: defaults)
        store.setDraft("Кстати, про субботу — ", chatId: "c1")
        XCTAssertEqual(ChatDraftStore(defaults: defaults).draft(chatId: "c1"), "Кстати, про субботу — ")
        store.setDraft("   \n", chatId: "c1")
        XCTAssertNil(store.drafts["c1"])
        XCTAssertEqual(ChatDraftStore(defaults: defaults).draft(chatId: "c1"), "")
    }

    func testRelativeReadTime() {
        XCTAssertTrue(ChatViewModel.relativeDayTime(Date()).hasPrefix("сегодня в "))
        let longAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        XCTAssertTrue(ChatViewModel.relativeDayTime(longAgo).contains(" в "))
        XCTAssertFalse(ChatViewModel.relativeDayTime(longAgo).hasPrefix("сегодня"))
    }
}
