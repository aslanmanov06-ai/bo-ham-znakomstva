import SwiftUI

@main
struct OrzuAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        AppTheme.applyUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                // Onest — шрифт по умолчанию для всего текста без явного стиля; гранат — цвет кнопок и переключателей.
                .font(.app(.body))
                .tint(.brand)
                .onOpenURL { GoogleAuth.handle($0) }
        }
    }
}
