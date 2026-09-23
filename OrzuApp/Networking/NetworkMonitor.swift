import Combine
import Foundation
import Network

extension Notification.Name {
    /// Сеть снова появилась: экраны догружают пропущенное (сокет не повторяет события, пришедшие без нас),
    /// очередь отправляет накопленные сообщения.
    static let networkBecameAvailable = Notification.Name("com.orzuapp.messenger.networkBecameAvailable")
}

/// Есть ли у устройства путь в интернет. Это подсказка для интерфейса и повода повторить запросы,
/// а не гарантия: сервер может быть недоступен и при «зелёной» сети — это решают ошибки самих запросов.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.update(isOnline: isOnline) }
        }
        monitor.start(queue: DispatchQueue(label: "com.orzuapp.messenger.network-monitor"))
    }

    private func update(isOnline newValue: Bool) {
        guard newValue != isOnline else { return }
        isOnline = newValue
        if newValue {
            NotificationCenter.default.post(name: .networkBecameAvailable, object: nil)
        }
    }
}
