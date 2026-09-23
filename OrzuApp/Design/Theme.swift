import SwiftUI
import UIKit

// Фирменный стиль «Бо Хам» — «Ночной гранат»: гранатовый основной цвет, шампанское золото для значков
// и второстепенных акцентов, тёплые тёмные (или светлые) поверхности. Шрифты: Unbounded — заголовки, Onest — текст.
// Все цвета динамические: светлая и тёмная версии переключаются вместе с системой или «Оформлением».

extension Color {
    /// Гранат: главные кнопки, лайк, выбранная вкладка, счётчики.
    static let brand = Color(light: 0xCF3350, dark: 0xE2455F)
    /// Тёмный гранат — вторая точка градиента главных кнопок, чтобы заливка не выглядела плоской.
    static let brandDeep = Color(light: 0xA8213F, dark: 0xB42A4C)
    /// Шампанское золото: значок «проверен», первое сообщение, совместимость.
    static let champagne = Color(light: 0x9C6A1C, dark: 0xF0C27B)
    /// Лёгкая гранатовая подложка: выбранные строки, плашки, чипы.
    static let brandSoft = Color(light: 0xFBE7EB, dark: 0x2C1D25)
    /// Лёгкая золотая подложка — под кнопкой первого сообщения и золотыми чипами.
    static let champagneSoft = Color(light: 0xF6ECDA, dark: 0x3A2E1E)

    /// Фон экранов: тёплый слоновой кости днём, сливово-чёрный ночью.
    static let appBackground = Color(light: 0xFAF6F3, dark: 0x120E12)
    /// Карточки, строки, поля ввода поверх фона.
    static let appSurface = Color(light: 0xFFFFFF, dark: 0x1D171C)
    /// Приподнятая поверхность внутри карточки: пузырь собеседника, вложенные плашки.
    static let appElevated = Color(light: 0xF3ECE8, dark: 0x282027)
    /// Тонкие границы и разделители.
    static let appLine = Color(light: 0xEADFD9, dark: 0x30262D)
    /// Заглушка на месте фото, пока оно грузится или его нет.
    static let appPlaceholder = Color(light: 0xE9DDD6, dark: 0x3A2A33)

    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// Заливка главных кнопок и лайка.
    static var brandFill: LinearGradient {
        LinearGradient(colors: [.brand, .brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Шрифты

/// Файлы лежат в Resources/Fonts и перечислены в UIAppFonts (project.yml). Имена — PostScript-имена начертаний.
enum AppFont {
    enum Family {
        case display, text
    }

    /// Начертание выбираем по имени файла: у статических шрифтов `.weight()` не всегда находит соседний файл семейства.
    static func name(_ family: Family, _ weight: Font.Weight) -> String {
        switch family {
        case .display:
            switch weight {
            case .bold, .heavy, .black: return "Unbounded-Bold"
            case .semibold: return "Unbounded-SemiBold"
            default: return "Unbounded-Medium"
            }
        case .text:
            switch weight {
            case .bold, .heavy, .black: return "Onest-Bold"
            case .semibold: return "Onest-SemiBold"
            case .medium: return "Onest-Medium"
            default: return "Onest-Regular"
            }
        }
    }

    /// Размеры как у системных стилей при стандартном Dynamic Type — дальше они масштабируются вместе с ними.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    /// Жирность по умолчанию — как у системного стиля: headline полужирный, остальные обычные.
    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}

extension Font {
    /// Текст интерфейса (Onest) со стилем Dynamic Type.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        .custom(AppFont.name(.text, weight ?? AppFont.defaultWeight(style)), size: AppFont.size(style), relativeTo: style)
    }

    /// Текст интерфейса фиксированного размера — для цифр и подписей внутри кругов и значков.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(.text, weight), fixedSize: size)
    }

    /// Заголовки (Unbounded). Широкий шрифт — поэтому на ступень мельче системного того же стиля.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .custom(AppFont.name(.display, weight), size: AppFont.size(style) * displayScale, relativeTo: style)
    }

    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(AppFont.name(.display, weight), fixedSize: size)
    }

    private static let displayScale: CGFloat = 0.82
}

enum AppTheme {
    /// Заголовки навигации и подписи вкладок рисует UIKit — ему шрифты задаём через appearance, один раз при запуске.
    @MainActor
    static func applyUIKitAppearance() {
        let navigation = UINavigationBar.appearance()
        if let large = UIFont(name: AppFont.name(.display, .semibold), size: 28) {
            navigation.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: AppFont.name(.text, .semibold), size: 17) {
            navigation.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
        if let tab = UIFont(name: AppFont.name(.text, .medium), size: 10) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
        }
    }
}

// MARK: - Общие элементы

/// Фон экранов: тёплая заливка и едва заметное гранатовое свечение сверху — на ровном цвете стекло выглядит плоским.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            RadialGradient(colors: [Color.brand.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Color.champagne.opacity(0.06), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Фон экрана со списком или формой: системная заливка списка прячется, под ним — фирменный фон.
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground())
    }

    /// Карточка поверх фона: светлая поверхность, тонкая граница, крупное скругление.
    func appCard(cornerRadius: CGFloat = AppMetrics.cardRadius, padding: CGFloat? = AppMetrics.cardPadding) -> some View {
        self
            .padding(padding ?? 0)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }
}

enum AppMetrics {
    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let buttonHeight: CGFloat = 54
    static let screenPadding: CGFloat = 16
}

/// Кнопки экранов: главная — гранатовая капсула, второстепенная — светлая с границей, тихая — только текст.
struct AppButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, quiet
    }

    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.body, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
            .padding(.horizontal, 20)
            .foregroundStyle(foreground)
            .background { background }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: .primary
        case .quiet: .brand
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill(.brandFill)
                .shadow(color: Color.brand.opacity(0.3), radius: 12, y: 6)
        case .secondary:
            Capsule().fill(Color.appSurface)
                .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
        case .quiet:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appQuiet: AppButtonStyle { AppButtonStyle(kind: .quiet) }
}

/// Счётчик непрочитанного или новых запросов.
struct CountBadge: View {
    let count: Int
    var tint: Color = .brand

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.app(size: 12, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(tint, in: Capsule())
    }
}

/// Круглая иконка-кнопка в шапке экрана (новый чат, пары, настройки): 44 pt — минимальная зона касания по HIG.
struct HeaderIconButton: View {
    let systemImage: String
    let title: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.appSurface, in: Circle())
                .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        CountBadge(count: badge)
                            .scaleEffect(0.85)
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
    }
}

/// Поле ввода на светлой подложке с иконкой слева — вход, регистрация, восстановление пароля.
struct AppField<Input: View>: View {
    let systemImage: String
    @ViewBuilder var field: Input

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            field
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Color.appSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }
}
