import LocalAuthentication
import SwiftUI

/// Оформление хранится только на этом устройстве (UserDefaults) — это личная настройка, сервер о ней не знает.
@MainActor
final class AppearanceSettings: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Как в системе"
            case .light: return "Светлая"
            case .dark: return "Тёмная"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum BubbleColor: String, CaseIterable, Identifiable {
        case garnet, blue, green, purple, orange, pink, graphite

        var id: String { rawValue }
        var color: Color {
            switch self {
            case .garnet: return .brand
            case .blue: return .blue
            case .green: return .green
            case .purple: return .purple
            case .orange: return .orange
            case .pink: return .pink
            case .graphite: return Color(white: 0.35)
            }
        }
        /// Для VoiceOver: rawValue — английские ключи для UserDefaults.
        var title: String {
            switch self {
            case .garnet: return "Гранат"
            case .blue: return "Синий"
            case .green: return "Зелёный"
            case .purple: return "Фиолетовый"
            case .orange: return "Оранжевый"
            case .pink: return "Розовый"
            case .graphite: return "Графит"
            }
        }
    }

    enum Wallpaper: String, CaseIterable, Identifiable {
        // Прежние «Небо», «Мята» и «Закат» убраны вместе со старой палитрой — у выбравших их станет «Без фона».
        case none, garnet, gold, night

        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "Без фона"
            case .garnet: return "Гранат"
            case .gold: return "Золото"
            case .night: return "Ночь"
            }
        }
        /// Полупрозрачные градиенты поверх фирменного фона — читаются и в светлой, и в тёмной теме.
        var gradient: LinearGradient? {
            let colors: [Color]
            switch self {
            case .none: return nil
            case .garnet: colors = [Color.brand.opacity(0.22), Color.brand.opacity(0.04)]
            case .gold: colors = [Color.champagne.opacity(0.22), Color.champagne.opacity(0.04)]
            case .night: colors = [Color(rgb: 0x5A1733).opacity(0.35), Color.black.opacity(0.25)]
            }
            return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static let shared = AppearanceSettings()

    private enum Key {
        static let theme = "appearance.theme"
        static let bubbleColor = "appearance.bubbleColor"
        static let wallpaper = "appearance.wallpaper"
    }

    @Published var theme: Theme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: Key.theme) } }
    @Published var bubbleColor: BubbleColor { didSet { UserDefaults.standard.set(bubbleColor.rawValue, forKey: Key.bubbleColor) } }
    @Published var wallpaper: Wallpaper { didSet { UserDefaults.standard.set(wallpaper.rawValue, forKey: Key.wallpaper) } }

    private init() {
        let defaults = UserDefaults.standard
        theme = defaults.string(forKey: Key.theme).flatMap(Theme.init(rawValue:)) ?? .system
        bubbleColor = defaults.string(forKey: Key.bubbleColor).flatMap(BubbleColor.init(rawValue:)) ?? .garnet
        wallpaper = defaults.string(forKey: Key.wallpaper).flatMap(Wallpaper.init(rawValue:)) ?? .none
    }
}

struct AppearanceView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
            }

            Section("Тема") {
                Picker("Тема", selection: $appearance.theme) {
                    ForEach(AppearanceSettings.Theme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Цвет моих сообщений") {
                HStack {
                    ForEach(AppearanceSettings.BubbleColor.allCases) { option in
                        Button { appearance.bubbleColor = option } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: appearance.bubbleColor == option ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(appearance.bubbleColor == option ? .isSelected : [])
                        if option != AppearanceSettings.BubbleColor.allCases.last { Spacer(minLength: 0) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Фон чата") {
                HStack(spacing: 10) {
                    ForEach(AppearanceSettings.Wallpaper.allCases) { option in
                        Button { appearance.wallpaper = option } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.appBackground)
                                    .overlay { option.gradient.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                                    .frame(height: 86)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(appearance.wallpaper == option ? Color.brand : Color.appLine, lineWidth: appearance.wallpaper == option ? 2 : 1)
                                    )
                                Text(option.title)
                                    .font(.app(.caption))
                                    .foregroundStyle(appearance.wallpaper == option ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.wallpaper == option ? .isSelected : [])
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .appScreenBackground()
        .navigationTitle("Оформление")
    }

    /// Как будет выглядеть переписка — сразу с выбранными цветом и фоном.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ассалому алейкум! Как дела?")
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.appLine, lineWidth: 1))
            HStack {
                Spacer()
                Text("Отлично, спасибо")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(appearance.bubbleColor.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .font(.app(.subheadline))
        .padding(14)
        .background {
            ZStack {
                Color.appBackground
                appearance.wallpaper.gradient
            }
        }
    }
}

// MARK: - Блокировка приложения

/// Блокировка по Face ID, Touch ID или коду-паролю телефона. Настройка этого устройства: переписку и анкету
/// не увидит тот, кому дали подержать разблокированный телефон. В переключателе приложений экран тоже закрыт.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private static let enabledKey = "appLock.enabled"

    @Published private(set) var isEnabled: Bool
    /// Приложение закрыто экраном блокировки: после запуска и после возвращения из фона.
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// На телефоне без код-пароля блокировать нечем — переключатель не показываем.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Какой способ предложит система — для подписи переключателя.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "код-пароль"
        }
    }

    /// Включение подтверждается сразу: иначе можно включить блокировку, которую потом не снять.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: "Включить блокировку приложения") else { return }
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
    }

    /// Приложение ушло в фон — при возвращении снова спросим Face ID.
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "Разблокировать приложение") {
            isLocked = false
        }
    }

    /// Выход из аккаунта: блокировку включал прошлый пользователь.
    func reset() {
        isEnabled = false
        isLocked = false
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
    }

    /// deviceOwnerAuthentication: если Face ID не узнал, система сама предложит код-пароль телефона.
    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Строка в настройках «Приложение».
struct AppLockToggle: View {
    @ObservedObject private var appLock = AppLock.shared

    var body: some View {
        if appLock.isAvailable || appLock.isEnabled {
            Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { value in Task { await appLock.setEnabled(value) } })) {
                SettingsLabel("Блокировка: \(appLock.methodName)", systemImage: "lock.fill", color: .champagne)
            }
            .disabled(appLock.isAuthenticating)
        }
    }
}

/// Накрывает всё приложение, пока оно заблокировано или не на экране (снимок для переключателя приложений).
struct AppLockView: View {
    @ObservedObject var appLock: AppLock

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text("Бо Хам заблокирован")
                    .font(.display(.title3))
                if appLock.isLocked {
                    Button("Разблокировать") {
                        Task { await appLock.unlock() }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(appLock.isAuthenticating)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                }
            }
        }
    }
}
