import SwiftUI

/// Цвета раздела знакомств — из общего стиля «Ночной гранат» (Design/Theme.swift) плюс общие пружины анимаций.
enum DatingStyle {
    static let rose = Color.brand
    /// Второй тон поздравлений и сердечек — шампанское золото.
    static let coral = Color.champagne
    static let plum = Color(light: 0x5A1733, dark: 0x3A1026)
    /// Первое сообщение — золотое, чтобы отличалось от лайка.
    static let intro = Color.champagne

    static let brandGradient = LinearGradient(colors: [.brand, .brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardCornerRadius: CGFloat = 28
    static let tileCornerRadius: CGFloat = 20

    /// Всё, что тянет палец, возвращается этой пружиной: быстро и с лёгким перелётом.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
}

/// Фон раздела — общий фирменный фон приложения.
struct DatingBackdrop: View {
    var body: some View {
        AppBackground()
    }
}

/// Тег анкеты. На фото — светлое стекло, на обычном фоне — лёгкая фирменная заливка.
struct DatingChip: View {
    let text: String
    var systemImage: String?
    var onPhoto = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.app(.footnote, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(onPhoto ? Color.white : DatingStyle.rose)
        .background {
            if onPhoto {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.white.opacity(0.12))
            } else {
                Capsule().fill(DatingStyle.rose.opacity(0.12))
            }
        }
    }
}

/// Процент совместимости кольцом: дуга дорисовывается при появлении, так число «читается» быстрее цифры.
struct CompatibilityRing: View {
    let score: Int
    var size: CGFloat = 54
    var lineWidth: CGFloat = 5
    var trackColor: Color = .white.opacity(0.25)

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Color.champagne, Color.champagne.opacity(0.7), Color.champagne], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(clampedScore)%")
                .font(.display(size: size * 0.24, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .onAppear {
            let target = Double(clampedScore) / 100
            if reduceMotion {
                progress = target
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { progress = target }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Совместимость \(clampedScore) процентов")
    }

    private var clampedScore: Int {
        min(max(score, 0), 100)
    }
}

/// Блик, пробегающий по заглушке, пока грузится фото или лента.
struct ShimmerModifier: ViewModifier {
    let active: Bool

    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width * 1.3)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

/// Кнопка чуть сжимается под пальцем — без этого круглые кнопки ощущаются «картонными».
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Круглые кнопки «пропустить / написать / лайк» — одинаковые в ленте и в открытой анкете.
struct DatingActionButton: View {
    enum Kind {
        case skip, intro, like
    }

    let kind: Kind
    var size: CGFloat = 60
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            label
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.impact(weight: kind == .like ? .medium : .light), trigger: taps)
        .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder
    private var label: some View {
        let icon = Image(systemName: iconName)
            .font(.system(size: size * 0.4, weight: .bold))
            .symbolEffect(.bounce, value: taps)
            .frame(width: size, height: size)
        switch kind {
        case .like:
            icon
                .foregroundStyle(.white)
                .background(.brandFill, in: Circle())
                .shadow(color: Color.brand.opacity(0.4), radius: 14, y: 7)
        case .skip:
            icon
                .foregroundStyle(.secondary)
                .background(Color.appSurface, in: Circle())
                .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
        case .intro:
            icon
                .foregroundStyle(DatingStyle.intro)
                .background(Color.champagneSoft, in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
        }
    }

    private var iconName: String {
        switch kind {
        case .skip: "xmark"
        case .intro: "paperplane.fill"
        case .like: "heart.fill"
        }
    }

    private var accessibilityTitle: String {
        switch kind {
        case .skip: "Пропустить"
        case .intro: "Написать"
        case .like: "Лайк"
        }
    }
}

/// Расходящиеся круги вокруг значка — «ищем людей рядом».
struct PulseRings: View {
    var color: Color = DatingStyle.rose

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ringCount = 3
    private let cycle: Double = 2.4

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(expanded ? 2.2 : 1)
                    .opacity(expanded ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: cycle)
                            .repeatForever(autoreverses: false)
                            .delay(cycle / Double(ringCount) * Double(index)),
                        value: expanded
                    )
            }
        }
        .onAppear { expanded = !reduceMotion }
        .allowsHitTesting(false)
    }
}

/// Сердечки, всплывающие снизу вверх, — фон для поздравления с парой и приветствия.
/// Canvas вместо десятка View: частицы перерисовываются каждый кадр, и так это дешевле.
struct FloatingHeartsView: View {
    var count = 16
    var colors: [Color] = [DatingStyle.rose, DatingStyle.coral, .white]

    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    for index in 0..<count {
                        drawHeart(index: index, elapsed: elapsed, in: &context, size: size)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Параметры каждого сердечка выводятся из его номера: без случайности картинка не «прыгает» при перерисовке.
    private func drawHeart(index: Int, elapsed: Double, in context: inout GraphicsContext, size: CGSize) {
        let seed = Double(index) + 1
        let speed = 0.06 + fraction(seed * 7.13) * 0.06
        let progress = fraction(elapsed * speed + fraction(seed * 3.7))
        let side = 12 + fraction(seed * 2.17) * 22
        let x = size.width * (0.06 + 0.88 * fraction(seed * 5.31)) + sin(elapsed * 1.3 + seed) * 16
        let y = size.height * (1.05 - progress * 1.15)

        var heart = context.resolve(Image(systemName: "heart.fill"))
        heart.shading = .color(colors[index % colors.count])
        context.opacity = sin(progress * .pi) * 0.7
        context.draw(heart, in: CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
    }

    private func fraction(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
