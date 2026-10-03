import Foundation

/// Лента знакомств: карточки, дневные лимиты и оценка анкет.
@MainActor
final class DatingFeedViewModel: ObservableObject {
    @Published private(set) var cards: [DatingFeedCard] = []
    @Published private(set) var limits: DailyLimits?
    @Published private(set) var isLoading = false
    /// Лента закрыта целиком: не подтверждено селфи или отмечено «мы нашли друг друга».
    @Published private(set) var blockedMessage: String?
    /// Взаимный лайк — показываем поздравление.
    @Published var newMatch: DatingMatch?
    @Published var errorMessage: String?
    /// Последняя оценённая карточка, если из неё не вышло пары: её можно вернуть кнопкой «Отменить».
    @Published private(set) var lastRated: DatingFeedCard?
    @Published private(set) var isUndoing = false
    /// Для пустой ленты: сколько людей подходит вообще и сколько сейчас в рулетке. nil — неизвестно, цифры не показываем.
    @Published private(set) var matchingCount: Int?
    @Published private(set) var rouletteOnline: Int?

    /// Кнопка видна, только если сервер умеет отмену (прислал undoLeft) и лимит на сегодня не кончился.
    var canUndo: Bool {
        lastRated != nil && (limits?.undoLeft ?? 0) > 0
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let feed = try await APIClient.shared.fetchDatingFeed()
            cards = feed.cards
            limits = feed.limits
            matchingCount = feed.matchingCount
            blockedMessage = nil
        } catch let error as APIError where error.code == ServerErrorCode.inCouple {
            cards = []
            blockedMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Пустая лента показывает, сколько людей подходит и сколько сейчас в рулетке. Если ленту опустошили свайпами,
    /// числа подходящих ещё нет — его отдаёт только запрос пустой ленты. Сбой не мешает: цифры просто не видны.
    func loadEmptyFeedStats() async {
        if matchingCount == nil { await load() }
        rouletteOnline = (try? await APIClient.shared.fetchRouletteStatus())?.online?.total
    }

    func like(_ card: DatingFeedCard) async {
        await rate(card, action: .like)
    }

    func skip(_ card: DatingFeedCard) async {
        await rate(card, action: .skip)
    }

    var likesLeft: Int? {
        limits?.likesLeft
    }

    private func rate(_ card: DatingFeedCard, action: SwipeAction) async {
        // Карточку убираем сразу: ждать ответа сервера незачем, а при ошибке вернём её на место.
        let index = cards.firstIndex(where: { $0.id == card.id })
        cards.removeAll { $0.id == card.id }
        do {
            let result = try await APIClient.shared.swipe(userId: card.profile.userId, action: action)
            limits = result.limits
            newMatch = result.match
            // Пару отменить нельзя — возвращать нечего.
            lastRated = result.match == nil ? card : nil
        } catch {
            if let index {
                cards.insert(card, at: min(index, cards.count))
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Карточка возвращается наверх стопки. Отказ сервера (время вышло, лимит) убирает кнопку.
    func undo() async {
        guard let card = lastRated, !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            let result = try await APIClient.shared.undoLastSwipe()
            if let updated = result.limits { limits = updated }
            lastRated = nil
            cards.removeAll { $0.id == card.id }
            cards.insert(card, at: 0)
        } catch let error as APIError where error.isTransient {
            errorMessage = error.localizedDescription
        } catch {
            lastRated = nil
            errorMessage = error.localizedDescription
        }
    }
}
