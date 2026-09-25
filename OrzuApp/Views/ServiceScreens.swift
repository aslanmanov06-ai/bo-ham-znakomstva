import SwiftUI

// Служебные экраны, которые закрывают приложение целиком или регистрацию: обслуживание, обязательное обновление,
// блокировка аккаунта, закрытая регистрация. Свёрстаны по макетам «Этап 4 — служебные экраны».

/// Крупная иконка в мягком круге с двумя расходящимися кольцами — как на экране кода из письма.
struct HaloIcon: View {
    let systemImage: String
    var tint: Color = .brand
    var fill: Color = .brandSoft

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 50, weight: .light))
            .foregroundStyle(tint)
            .frame(width: 132, height: 132)
            .background(fill, in: Circle())
            .background(Circle().fill(tint.opacity(0.08)).padding(-16))
            .background(Circle().fill(tint.opacity(0.04)).padding(-34))
            .padding(.bottom, 26)
            .accessibilityHidden(true)
    }
}

/// Раскладка служебного экрана: иконка и текст по центру, кнопки прижаты к низу.
private struct ServiceScreenLayout<Content: View, Actions: View>: View {
    var topPadding: CGFloat = 100
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                content
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.top, topPadding)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) { actions }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: 440)
        }
        .background(AppBackground())
    }
}

private struct ServiceTitle: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        Text(text)
            .font(.display(size: size))
            .lineSpacing(3)
    }
}

private struct ServiceText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.app(.subheadline))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
    }
}

/// Карточка «Причина» — на экранах блокировки и запроса селфи.
struct ReasonCard: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ПРИЧИНА")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .kerning(0.3)
            Text(reason)
                .font(.app(.callout))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .appCard(cornerRadius: 20, padding: nil)
    }
}

// MARK: - Режим обслуживания

struct MaintenanceView: View {
    @ObservedObject var status: AppStatus
    @State private var isChecking = false

    var body: some View {
        ServiceScreenLayout {
            HaloIcon(systemImage: "wrench.adjustable", tint: .champagne, fill: .champagneSoft)
            ServiceTitle(text: "Скоро вернёмся")
            ServiceText(text: status.maintenanceMessage)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left")
                    .foregroundStyle(.secondary)
                Text("Сообщения, которые вы напишете сейчас, сохранятся и уйдут сами, когда сервер заработает.")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .appCard(cornerRadius: 20, padding: nil)
            .padding(.top, 10)
        } actions: {
            Text("Проверяем сами каждые 30 секунд")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
            Button {
                isChecking = true
                Task {
                    await status.refresh()
                    isChecking = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Проверить сейчас")
                }
            }
            .buttonStyle(.appSecondary)
            .disabled(isChecking)
        }
    }
}

// MARK: - Обязательное обновление

struct UpdateRequiredView: View {
    let minimumVersion: String

    var body: some View {
        ServiceScreenLayout {
            HaloIcon(systemImage: "arrow.down.app")
            ServiceTitle(text: "Обновите приложение")
            ServiceText(text: "Эта версия Бо Хам больше не работает. Установите новую из App Store — переписки, пары и анкета сохранятся.")
            HStack(spacing: 8) {
                versionPill("У вас", AppVersion.current, highlighted: false)
                versionPill("Нужна", minimumVersion, highlighted: true)
            }
            .padding(.top, 6)
        } actions: {
            Button {
                UIApplication.shared.open(AppConfig.appStoreURL)
            } label: {
                Label("Обновить в App Store", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.appPrimary)
        }
    }

    private func versionPill(_ title: String, _ version: String, highlighted: Bool) -> some View {
        (Text("\(title) ").foregroundStyle(highlighted ? Color.primary : Color.secondary) + Text(version).fontWeight(.semibold).foregroundStyle(Color.primary))
            .font(.app(.footnote))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(highlighted ? Color.brand.opacity(0.14) : Color.appSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(highlighted ? Color.brand.opacity(0.35) : Color.appLine, lineWidth: 1))
    }
}

// MARK: - Блокировка аккаунта

struct AccountBannedView: View {
    let notice: BanNotice
    let onLogout: () -> Void

    @State private var showAppeal = false
    @State private var appealSent = false

    private static let untilFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter
    }()

    var body: some View {
        ServiceScreenLayout(topPadding: 80) {
            HaloIcon(systemImage: "xmark.shield")
            if let until = notice.bannedUntil, !notice.permanent {
                ServiceTitle(text: "Аккаунт временно заблокирован", size: 21)
                Label("до \(Self.untilFormat.string(from: until))", systemImage: "clock")
                    .font(.app(.subheadline))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Color.brand.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.brand.opacity(0.35), lineWidth: 1))
            } else {
                ServiceTitle(text: "Аккаунт заблокирован", size: 21)
                ServiceText(text: "Бессрочно — за нарушение правил сообщества")
            }
            if let reason = notice.reason {
                ReasonCard(reason: reason)
                    .padding(.top, 6)
            }
            ServiceText(text: appealSent
                ? "Обжалование отправлено. Модератор пересмотрит решение, ответ придёт на почту аккаунта."
                : "Считаете решение ошибкой — напишите нам, модератор пересмотрит его.")
        } actions: {
            // Без пропуска обжаловать нечем: он приходит с отказом сервера и живёт час.
            if let token = notice.appealToken, !appealSent {
                Button {
                    showAppeal = true
                } label: {
                    Label("Обжаловать", systemImage: "envelope")
                }
                .buttonStyle(.appPrimary)
                .sheet(isPresented: $showAppeal) {
                    NavigationStack {
                        NewSupportTicketView(
                            fixedCategory: .appeal,
                            submit: { _, text in try await APIClient.shared.appealBan(appealToken: token, text: text) },
                            onSent: { _ in appealSent = true }
                        )
                    }
                    .tint(.brand)
                }
            }
            Button("Выйти из аккаунта", action: onLogout)
                .buttonStyle(.appSecondary)
        }
    }
}

// MARK: - Регистрация закрыта

/// Показывается вместо формы регистрации (паролем и через Google). Вход при этом работает.
struct RegistrationClosedView: View {
    let onBack: () -> Void

    var body: some View {
        ServiceScreenLayout(topPadding: 50) {
            HaloIcon(systemImage: "person.crop.circle.badge.xmark")
            ServiceTitle(text: "Регистрация временно закрыта", size: 21)
            ServiceText(text: "Новые аккаунты сейчас не создаются. Загляните позже — обычно это ненадолго.")
            ServiceText(text: "Если аккаунт у вас уже есть, вход работает как обычно.")
                .padding(.top, 4)
        } actions: {
            Button("Войти в аккаунт", action: onBack)
                .buttonStyle(.appPrimary)
        }
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                        Text("Назад")
                    }
                }
            }
        }
    }
}
