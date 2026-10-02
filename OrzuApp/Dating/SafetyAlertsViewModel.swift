import Combine
import Foundation

/// Уведомления, которые важнее текущего экрана: чужая тревога SOS и санкция модератора.
/// Живут на уровне приложения — их показывает RootView из любой вкладки.
@MainActor
final class SafetyAlertsViewModel: ObservableObject {
    static let shared = SafetyAlertsViewModel()

    /// Открытая тревога того, кто добавил вас в доверенные контакты.
    @Published var incomingAlert: SosAlert?
    /// Тревоги, от которых давно нет геопозиции; новая точка снимает отметку.
    @Published private(set) var signalLostAlertIds: Set<String> = []
    @Published var sanction: SanctionNotice?
    /// Встреча, которой поделился тот, кто добавил вас в доверенные контакты.
    @Published var sharedMeeting: SharedMeeting?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)
    }

    /// Тап по push о тревоге: самого текста тревоги в уведомлении нет, поэтому забираем её с сервера.
    func open(alertId: String) async {
        incomingAlert = try? await APIClient.shared.fetchSosAlert(alertId: alertId)
    }

    private func handle(event: ServerEvent) {
        switch event {
        case .sosAlert(let alert):
            signalLostAlertIds.remove(alert.id)
            incomingAlert = alert
        case .sosSignalLost(let alert):
            signalLostAlertIds.insert(alert.id)
            incomingAlert = alert
        case .sosClosed(let alert):
            signalLostAlertIds.remove(alert.id)
            // Тревогу закрыли — снимаем экран, если показывали именно её.
            if incomingAlert?.id == alert.id {
                incomingAlert = nil
            }
        case .accountSanction(let type, let reason):
            sanction = SanctionNotice(type: type, reason: reason)
        case .meetingShared(let meeting):
            sharedMeeting = meeting
        default:
            break
        }
    }
}

struct SanctionNotice: Identifiable {
    let type: String
    let reason: String
    let id = UUID()

    var title: String {
        switch type {
        case "WARNING": return String(localized: "Предупреждение")
        case "FEED_HIDDEN": return String(localized: "Анкета скрыта")
        case "SUSPENSION": return String(localized: "Аккаунт временно заблокирован")
        case "BAN": return String(localized: "Аккаунт заблокирован")
        default: return String(localized: "Решение модератора")
        }
    }
}
