import Foundation

/// Сетка всех анкет нужного пола: фильтры, постраничная догрузка и лайк без ленты.
@MainActor
final class DatingBrowseViewModel: ObservableObject {
    private static let filtersKey = "com.orzuapp.messenger.datingBrowseFilters"

    @Published private(set) var cards: [DatingBrowseCard] = []
    @Published private(set) var filters: DatingBrowseFilters
    @Published private(set) var isLoading = false
    /// Сетка закрыта целиком: отмечено «мы нашли друг друга».
    @Published private(set) var blockedMessage: String?
    /// Взаимный лайк — показываем поздравление.
    @Published var newMatch: DatingMatch?
    @Published var errorMessage: String?

    private var nextCursor: String?
    /// Номер загрузки: ответ устаревшего запроса (фильтры успели поменять) не должен затереть свежий.
    private var generation = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        filters = Self.loadFilters(from: defaults)
    }

    var hasMore: Bool {
        nextCursor != nil
    }

    /// Новые фильтры запоминаются на устройстве; сетку перезагружает экран — он следит за filters.
    func apply(_ newFilters: DatingBrowseFilters) {
        filters = newFilters
        do {
            defaults.set(try JSONEncoder().encode(newFilters), forKey: Self.filtersKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await APIClient.shared.browseDatingProfiles(filters: filters, cursor: nil)
            guard current == generation else { return }
            cards = page.cards
            nextCursor = page.nextCursor
            blockedMessage = nil
        } catch let error as APIError where error.code == ServerErrorCode.inCouple {
            guard current == generation else { return }
            cards = []
            nextCursor = nil
            blockedMessage = error.localizedDescription
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Долистали до конца — следующая страница. Повторный вызов, пока идёт загрузка, ничего не делает.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await APIClient.shared.browseDatingProfiles(filters: filters, cursor: cursor)
            guard current == generation else { return }
            let known = Set(cards.map(\.id))
            cards += page.cards.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func like(_ card: DatingFeedCard) async {
        // Сердечко на плитке ставим сразу, при ошибке — снимаем.
        setLiked(true, userId: card.profile.userId)
        do {
            let result = try await APIClient.shared.swipe(userId: card.profile.userId, action: .like)
            newMatch = result.match
        } catch {
            setLiked(false, userId: card.profile.userId)
            errorMessage = error.localizedDescription
        }
    }

    /// Пропуск из поиска по @username: в сетке анкета остаётся, но из ленты уйдёт.
    func skip(_ card: DatingFeedCard) async {
        do {
            _ = try await APIClient.shared.swipe(userId: card.profile.userId, action: .skip)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Первое сообщение ставит лайк на сервере — отмечаем его и в сетке.
    private func setLiked(_ liked: Bool, userId: String) {
        guard let index = cards.firstIndex(where: { $0.id == userId }) else { return }
        cards[index].liked = liked
    }

    static func forgetFilters(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: filtersKey)
    }

    private static func loadFilters(from defaults: UserDefaults) -> DatingBrowseFilters {
        guard let data = defaults.data(forKey: filtersKey) else { return DatingBrowseFilters() }
        guard let filters = try? JSONDecoder().decode(DatingBrowseFilters.self, from: data) else {
            // Формат фильтров поменялся в новой версии — начинаем без фильтров.
            defaults.removeObject(forKey: filtersKey)
            return DatingBrowseFilters()
        }
        return filters
    }
}
