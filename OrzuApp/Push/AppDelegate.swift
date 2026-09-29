import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Создаём заранее, чтобы делегат уведомлений был назначен до того, как система доставит тап по push.
        _ = PushManager.shared
        // PKPushRegistry должен существовать к моменту, когда iOS запускает приложение ради VoIP-push о звонке.
        _ = CallManager.shared
        return true
    }

    /// Фоновая загрузка файла закончилась, пока приложение было выгружено: iOS запустила его, чтобы доставить результат.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploads.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundUploads.shared.handleEvents(completionHandler: completionHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error: error)
    }
}
