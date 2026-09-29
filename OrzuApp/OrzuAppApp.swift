import BackgroundTasks
import SwiftUI
import os

@main
struct OrzuAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { BackgroundRefresh.schedule() }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
        }
    }
}

/// Фоновое обновление: iOS будит свёрнутое приложение, когда сочтёт нужным (обычно несколько раз в день,
/// чаще у тех, кто открывает его часто). Досылаем неотправленное и обновляем список чатов на устройстве —
/// после перерыва приложение сразу показывает свежий список, даже если система успела его выгрузить.
enum BackgroundRefresh {
    /// Совпадает с BGTaskSchedulerPermittedIdentifiers в Info.plist.
    static let taskIdentifier = "com.orzuapp.messenger.refresh"
    /// Раньше iOS всё равно не разбудит, а просить чаще — тратить батарею.
    private static let minimumInterval: TimeInterval = 15 * 60
    private static let logger = Logger(subsystem: "com.orzuapp.messenger", category: "BackgroundRefresh")

    static func schedule() {
        guard TokenStore.shared.accessToken != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            // Повторная заявка с тем же id заменяет прежнюю — дублей не будет.
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // В симуляторе и при выключенном «Обновлении контента» — не ошибка приложения.
            logger.info("Фоновое обновление не запланировано: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    static func run() async {
        // Следующее — сразу: одна заявка будит приложение один раз.
        schedule()
        guard TokenStore.shared.accessToken != nil else { return }
        await MessageOutbox.shared.sendPending()
        do {
            _ = try await APIClient.shared.fetchChats()
        } catch {
            logger.info("Список чатов в фоне не обновился: \(error.localizedDescription, privacy: .public)")
        }
    }
}
