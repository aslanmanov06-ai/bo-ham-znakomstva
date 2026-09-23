import SwiftUI

// Liquid Glass из iOS 26 с запасным вариантом на материалах для iOS 17–18.
// По HIG стекло — только у слоя навигации и элементов управления; контент (пузыри, строки списков) остаётся непрозрачным.
// `#if compiler(>=6.2)` — чтобы проект собирался и Xcode без SDK iOS 26: там API стекла просто нет.

extension View {
    /// Стеклянная подложка кнопки, поля или плашки. `interactive` — стекло откликается на касание (только iOS 26).
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            materialSurface(in: shape, tint: tint)
        }
        #else
        materialSurface(in: shape, tint: tint)
        #endif
    }

    private func materialSurface<S: Shape>(in shape: S, tint: Color?) -> some View {
        background {
            shape.fill(.ultraThinMaterial)
            if let tint {
                shape.fill(tint.opacity(0.85))
            }
        }
        .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 0.5))
    }

    /// Главная кнопка экрана: стекло с акцентной заливкой.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    /// Второстепенная кнопка: прозрачное стекло.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// Панель у нижнего края поверх прокрутки. В iOS 26 контент под ней мягко растворяется (scroll edge effect).
    @ViewBuilder
    func bottomGlassBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            safeAreaInset(edge: .bottom, content: bar)
        }
        #else
        safeAreaInset(edge: .bottom, content: bar)
        #endif
    }

    /// Панель вкладок сворачивается при прокрутке вниз, как в системных приложениях iOS 26.
    @ViewBuilder
    func tabBarMinimizesOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Объединяет соседние стеклянные элементы: в iOS 26 они сливаются и перетекают друг в друга при анимации.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Фон под стеклом: стеклу нужно, что преломлять, — на ровной заливке оно выглядит плоским.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(iOS 18, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.4], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: colors
            )
        } else {
            LinearGradient(colors: [colors[0], colors[4], colors[8]], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Фирменные тона «Ночного граната»: гранат, слива и капля шампанского на тёплом фоне.
    private var colors: [Color] {
        let garnet = Color(rgb: 0xE2455F)
        let plum = Color(rgb: 0x5A1733)
        let champagne = Color(rgb: 0xF0C27B)
        let night = Color(rgb: 0x120E12)
        let ivory = Color(rgb: 0xFAF6F3)
        return colorScheme == .dark
            ? [plum, garnet.opacity(0.7), plum.opacity(0.8),
               night, plum.opacity(0.7), garnet.opacity(0.35),
               night, night, champagne.opacity(0.18)]
            : [garnet.opacity(0.35), champagne.opacity(0.35), garnet.opacity(0.22),
               ivory, garnet.opacity(0.12), champagne.opacity(0.25),
               ivory, ivory, garnet.opacity(0.18)]
    }
}
