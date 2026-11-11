import CoreLocation
import Foundation

/// Разовый запрос геопозиции: для расстояния в ленте и для SOS. Постоянное слежение приложению не нужно,
/// поэтому запрашиваем координаты по требованию и сразу отпускаем.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return String(localized: "Разрешите доступ к геопозиции в настройках")
            case .unavailable: return String(localized: "Не удалось определить геопозицию")
            }
        }
    }

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation, Error>] = []
    /// Без спутников и Wi-Fi Core Location может молчать минутами — в SOS столько ждать нельзя.
    /// Время на системный вопрос о доступе сюда не входит: отсчёт идёт с момента запроса координат.
    private static let timeout: Duration = .seconds(15)
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Человек ещё не отвечал на системный вопрос о геопозиции — его можно задать.
    var isUndecided: Bool {
        manager.authorizationStatus == .notDetermined
    }

    /// Доступ уже дан — координаты можно взять, не показывая системный вопрос.
    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    func current() async throws -> CLLocation {
        // Запрос уже идёт (фоновое обновление расстояния, слежение SOS) — ждём его же ответа, а не отказываем:
        // иначе нажатый в этот момент SOS выдал бы ошибку.
        return try await withCheckedThrowingContinuation { continuation in
            let isFirst = waiters.isEmpty
            waiters.append(continuation)
            guard isFirst else { return }
            switch manager.authorizationStatus {
            case .notDetermined:
                // Ждём ответа пользователя: запрос координат до разрешения завершился бы ошибкой.
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                requestLocation()
            default:
                finish(.failure(LocationError.denied))
            }
        }
    }

    private func requestLocation() {
        manager.requestLocation()
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled, let self else { return }
            // Точной точки нет, но система могла недавно определить место — для SOS это лучше, чем ничего.
            self.finishWithRecent(or: LocationError.unavailable)
        }
    }

    /// Точной точки нет, но система могла недавно определить место — для SOS это лучше, чем ничего.
    private func finishWithRecent(or error: Error) {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -300 {
            finish(.success(recent))
        } else {
            finish(.failure(error))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard !waiters.isEmpty else { return }
            switch status {
            case .notDetermined:
                break
            case .authorizedWhenInUse, .authorizedAlways:
                self.requestLocation()
            default:
                finish(.failure(LocationError.denied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            guard let last else { return finish(.failure(LocationError.unavailable)) }
            finish(.success(last))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            guard !waiters.isEmpty else { return }
            // В помещении Core Location быстро сдаётся (locationUnknown) — пробуем недавнюю точку, а не роняем SOS.
            if denied { finish(.failure(LocationError.denied)) } else { finishWithRecent(or: error) }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let resumed = waiters
        waiters = []
        for waiter in resumed { waiter.resume(with: result) }
    }
}
