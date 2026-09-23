import Combine
import Foundation

/// Пары и первые сообщения. Обновляется и по WebSocket: пара, входящее сообщение или разрыв
/// приходят сразу, без перезагрузки экрана.
@MainActor
final class MatchesViewModel: ObservableObject {
    @Published private(set) var matches: [DatingMatch] = []
    @Published private(set) var incoming: [IncomingIntro] = []
    @Published private(set) var sent: [SentIntro] = []
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
        do {
            matches = try await APIClient.shared.fetchMatches()
            let intros = try await APIClient.shared.fetchIntros()
            incoming = intros.incoming
            sent = intros.sent
        } catch let error as APIError where error.code == ServerErrorCode.inCouple {
            // Пара найдена: лента и первые сообщения закрыты, но сами пары остаются видны.
            incoming = []
            sent = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ответ на первое сообщение создаёт пару — она сразу появляется в списке.
    func reply(to intro: IncomingIntro, text: String) async -> DatingMatch? {
        do {
            let match = try await APIClient.shared.replyToIntro(introId: intro.id, text: text)
            incoming.removeAll { $0.id == intro.id }
            upsert(match)
            return match
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func decline(_ intro: IncomingIntro) async {
        do {
            try await APIClient.shared.declineIntro(introId: intro.id)
            incoming.removeAll { $0.id == intro.id }
        } catch {
            errorMessage = error.localizedDescription
        }
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
            // Пара могла возникнуть из первого сообщения — оно больше не ждёт ответа.
            incoming.removeAll { $0.from.userId == match.partner.userId }
            sent.removeAll { $0.to.userId == match.partner.userId }
        case .datingIntro(let intro):
            incoming.removeAll { $0.id == intro.id }
            incoming.insert(intro, at: 0)
        case .datingUnmatched(let matchId, _):
            matches.removeAll { $0.id == matchId }
        default:
            break
        }
    }
}
