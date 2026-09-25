import SwiftUI
import UserNotifications

/// Какие push присылать и показывать ли их текст на экране блокировки.
struct NotificationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemDenied = false

    var body: some View {
        Form {
            if systemDenied {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 38, height: 38)
                                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Уведомления выключены в iPhone").font(.app(.subheadline, weight: .semibold))
                                Text("Без них не узнаете о новых парах и сообщениях")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Открыть настройки iPhone", action: openSystemSettings)
                            .buttonStyle(.appSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let notifications = viewModel.settings?.notifications {
                Section("О чём сообщать") {
                    toggle("Сообщения", subtitle: "В чатах и ответы на ваши запросы", systemImage: "message.fill", color: .brand, keyPath: \.messages, in: notifications)
                    toggle("Пары и «Путь к браку»", subtitle: "Взаимный лайк, новые шаги пары", systemImage: "heart.fill", color: .brand, keyPath: \.matches, in: notifications)
                    toggle("Первые сообщения", subtitle: "И запросы на переписку", systemImage: "sparkles", color: .champagne, keyPath: \.intros, in: notifications)
                    toggle("Встречи", subtitle: "Приглашения и напоминания", systemImage: "calendar", color: .champagne, keyPath: \.meetings, in: notifications)
                }
                Section("От команды Бо Хам") {
                    toggle("Новости приложения", subtitle: "Новые функции и важные объявления", systemImage: "megaphone.fill", color: .champagne, keyPath: \.news, in: notifications)
                }
                Section {
                    toggle("Показывать имя и текст", subtitle: "Иначе — только «Бо Хам · Новое сообщение»", systemImage: nil, color: .brand, keyPath: \.preview, in: notifications)
                } header: {
                    Text("Экран блокировки")
                } footer: {
                    Text("SOS, решения модераторов и ответы поддержки приходят всегда. Звук отдельного чата отключается в самом чате.")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Уведомления")
        .task { await refreshSystemStatus() }
        // Вернулись из системных настроек — разрешение могло измениться.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshSystemStatus() } }
        }
    }

    private func toggle(
        _ title: String,
        subtitle: String,
        systemImage: String?,
        color: Color,
        keyPath: WritableKeyPath<NotificationSettings, Bool>,
        in current: NotificationSettings
    ) -> some View {
        Toggle(isOn: Binding(
            get: { current[keyPath: keyPath] },
            set: { value in
                var updated = current
                updated[keyPath: keyPath] = value
                Task { await viewModel.updateNotifications(updated) }
            }
        )) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.brand)
    }

    private func refreshSystemStatus() async {
        systemDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
