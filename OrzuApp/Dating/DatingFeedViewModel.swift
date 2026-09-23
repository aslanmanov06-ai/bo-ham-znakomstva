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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let feed = try await APIClient.shared.fetchDatingFeed()
            cards = feed.cards
            limits = feed.limits
            blockedMessage = nil
        } catch let error as APIError where error.code == ServerErrorCode.inCouple {
            cards = []
            blockedMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
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
        } catch {
            if let index {
                cards.insert(card, at: min(index, cards.count))
            }
            errorMessage = error.localizedDescription
        }
    }
}
