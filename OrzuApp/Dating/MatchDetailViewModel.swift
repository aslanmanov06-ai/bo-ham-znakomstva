import Combine
import Foundation

/// Одна пара: «Путь к браку» и встречи. Изменения второго участника приходят по WebSocket.
@MainActor
final class MatchDetailViewModel: ObservableObject {
    @Published private(set) var journey: JourneyView?
    @Published private(set) var meetings: [DatingMeeting] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var sharedWithCount: Int?

    private let matchId: String
    private var cancellables = Set<AnyCancellable>()

    init(matchId: String) {
        self.matchId = matchId
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)
    }

    func load() async {
        do {
            journey = try await APIClient.shared.fetchJourney(matchId: matchId)
            meetings = try await APIClient.shared.fetchMeetings(matchId: matchId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Предложить ступень; если её уже предложил партнёр — это согласие, и ступень подтверждается.
    func proposeStage(_ stage: String) async {
        await run { self.journey = try await APIClient.shared.proposeJourneyStage(matchId: self.matchId, stage: stage) }
    }

    func dropProposal() async {
        await run { self.journey = try await APIClient.shared.dropJourneyStageProposal(matchId: self.matchId) }
    }

    func toggleChecklist(_ code: String) async {
        guard let journey else { return }
        var items = journey.checklist.mine
        if let index = items.firstIndex(of: code) {
            items.remove(at: index)
        } else {
            items.append(code)
        }
        await run { self.journey = try await APIClient.shared.setJourneyChecklist(matchId: self.matchId, items: items) }
    }

    func proposeMeeting(startsAt: Date, place: String, note: String?) async {
        await run {
            let meeting = try await APIClient.shared.proposeMeeting(matchId: self.matchId, startsAt: startsAt, place: place, note: note)
            self.upsert(meeting)
        }
    }

    func accept(_ meeting: DatingMeeting) async {
        await run { self.upsert(try await APIClient.shared.acceptMeeting(meetingId: meeting.id)) }
    }

    func decline(_ meeting: DatingMeeting) async {
        await run { self.upsert(try await APIClient.shared.declineMeeting(meetingId: meeting.id)) }
    }

    func cancel(_ meeting: DatingMeeting) async {
        await run { self.upsert(try await APIClient.shared.cancelMeeting(meetingId: meeting.id)) }
    }

    func reschedule(_ meeting: DatingMeeting, startsAt: Date, place: String?, note: String?) async {
        await run {
            let updated = try await APIClient.shared.rescheduleMeeting(meetingId: meeting.id, startsAt: startsAt, place: place, note: note)
            self.upsert(updated)
            // Перенос закрывает прежнее приглашение — перечитываем историю, чтобы статусы совпали с сервером.
            self.meetings = try await APIClient.shared.fetchMeetings(matchId: self.matchId)
        }
    }

    func share(_ meeting: DatingMeeting) async {
        await run { self.sharedWithCount = try await APIClient.shared.shareMeeting(meetingId: meeting.id) }
    }

    /// Ближайшее приглашение, которое ещё чего-то ждёт: его и показываем наверху экрана.
    var activeMeeting: DatingMeeting? {
        meetings
            .filter { ($0.status == .proposed && !$0.expired) || ($0.status == .accepted && $0.startsAt > Date()) }
            .min { $0.startsAt < $1.startsAt }
    }

    private func upsert(_ meeting: DatingMeeting) {
        meetings.removeAll { $0.id == meeting.id }
        meetings.insert(meeting, at: 0)
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .datingJourney(let matchId) where matchId == self.matchId:
            Task { await load() }
        case .datingMeeting(let meeting) where meeting.matchId == self.matchId:
            upsert(meeting)
        default:
            break
        }
    }
}
