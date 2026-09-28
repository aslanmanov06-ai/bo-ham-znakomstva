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
                .onOpenURL { url in
                    // Ссылки на людей и каналы (в том числе Universal Links) — остальное отдаём Google Sign-In.
                    if let link = DeepLink.parse(url) {
                        PushManager.shared.pendingDeepLink = link
                    } else {
                        GoogleAuth.handle(url)
                    }
                }
        }
    }
}
