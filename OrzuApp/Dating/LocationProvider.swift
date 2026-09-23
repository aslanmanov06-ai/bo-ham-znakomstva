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
            case .denied: return "Разрешите доступ к геопозиции в настройках"
            case .unavailable: return "Не удалось определить геопозицию"
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

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
        // Один запрос за раз: второй ждать нечего — координаты нужны здесь и сейчас.
        if continuation != nil { throw LocationError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                // Ждём ответа пользователя: запрос координат до разрешения завершился бы ошибкой.
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(.failure(LocationError.denied))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard continuation != nil else { return }
            switch status {
            case .notDetermined:
                break
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
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
        Task { @MainActor in
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
