import Combine
import Foundation

/// Пары: новые — кружками в «Чатах», у каждой — страница «Путь к браку». Первые сообщения живут в общем
/// ящике запросов (ChatRequestsView). Обновляется и по WebSocket: пара или разрыв приходят сразу.
@MainActor
final class MatchesViewModel: ObservableObject {
    @Published private(set) var matches: [DatingMatch] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Пары второстепенны для списка чатов: без сети остаются прежними, ошибкой экран не мигает.
        guard let loaded = try? await APIClient.shared.fetchMatches() else { return }
        matches = loaded
    }

    func unmatch(_ match: DatingMatch) async {
        do {
            try await APIClient.shared.unmatch(matchId: match.id)
            matches.removeAll { $0.id == match.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upsert(_ match: DatingMatch) {
        matches.removeAll { $0.id == match.id }
        matches.insert(match, at: 0)
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .datingMatch(let match):
            upsert(match)
        case .datingUnmatched(let matchId, _):
            matches.removeAll { $0.id == matchId }
        default:
            break
        }
    }
}
