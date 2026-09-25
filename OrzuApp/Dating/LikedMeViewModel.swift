import Combine
import Foundation

/// «Вас лайкнули»: кто лайкнул меня из ленты, а я ещё не ответил. Ответ — лайк (пара) или пропуск.
@MainActor
final class LikedMeViewModel: ObservableObject {
    @Published private(set) var cards: [DatingLikedCard] = []
    @Published private(set) var isLoading = false
    /// Ответный лайк — это пара: показываем поздравление.
    @Published var newMatch: DatingMatch?
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Новый лайк приходит по сокету — полоса в ленте и экран обновляются сразу.
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard case .datingLiked = event else { return }
                Task { await self?.load() }
            }
            .store(in: &cancellables)
    }

    /// Ошибку показывает только экран «Вас лайкнули»: полоса в ленте без сети просто не появится.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await APIClient.shared.fetchLikedMe().cards
        } catch let error as APIError where error.isTransient || error.code == ServerErrorCode.inCouple {
            // Без сети оставляем прежний список; «нашли друг друга» — лента закрыта, лайков не показываем.
            if error.code == ServerErrorCode.inCouple { cards = [] }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(_ liked: DatingLikedCard, action: SwipeAction) async {
        // Карточку убираем сразу; при ошибке вернём на место.
        let index = cards.firstIndex(where: { $0.id == liked.id })
        cards.removeAll { $0.id == liked.id }
        do {
            newMatch = try await APIClient.shared.swipe(userId: liked.card.profile.userId, action: action).match
        } catch {
            if let index { cards.insert(liked, at: min(index, cards.count)) }
            errorMessage = error.localizedDescription
        }
    }
}
