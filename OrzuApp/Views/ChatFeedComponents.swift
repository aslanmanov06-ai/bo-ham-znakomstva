import SwiftUI
import UIKit

// MARK: - Даты и разделители

/// Капсула с датой: в ленте — на поверхности, плавающая над лентой — на стекле с тенью.
struct DateChip: View {
    let text: String
    var floating = false

    var body: some View {
        Text(text)
            .font(.app(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background {
                if floating {
                    Capsule().fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 7, y: 4)
                } else {
                    Capsule().fill(Color.appSurface)
                }
            }
            .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// «3 новых сообщения» — гранатовая черта, тающая к краям.
struct UnreadDivider: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            line(towards: .leading)
            Text(RussianPlural.newMessages(count))
                .font(.app(size: 12, weight: .bold))
                .foregroundStyle(Color.brand)
                .fixedSize()
            line(towards: .trailing)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func line(towards edge: HorizontalEdge) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Color.brand.opacity(0), Color.brand],
                startPoint: edge == .leading ? .leading : .trailing,
                endPoint: edge == .leading ? .trailing : .leading
            ))
            .frame(height: 1)
    }
}

// MARK: - «Печатает»

/// Три точки, подпрыгивающие волной (цикл 1,2 с). С «Уменьшением движения» — неподвижные.
struct TypingDots: View {
    var color: Color = .secondary
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.45) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = Self.phase(time: time, index: index)
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(reduceMotion ? 0.7 : 0.45 + 0.55 * phase)
                        .offset(y: reduceMotion ? 0 : -size * 0.6 * phase)
                }
            }
            .frame(height: size * 1.8)
        }
        .accessibilityHidden(true)
    }

    /// 0…1: подъём точки. Каждая следующая отстаёт на 0,15 с; 60 % цикла точка лежит.
    static func phase(time: TimeInterval, index: Int) -> Double {
        let cycle = 1.2
        let t = (time - Double(index) * 0.15).truncatingRemainder(dividingBy: cycle) / cycle
        let local = t < 0 ? t + 1 : t
        guard local < 0.6 else { return 0 }
        return sin(local / 0.6 * .pi)
    }
}

/// Пузырь собеседника с точками внизу ленты.
struct TypingBubble: View {
    let name: String

    var body: some View {
        HStack {
            TypingDots()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appSurface, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous).stroke(Color.appLine, lineWidth: 1))
            Spacer(minLength: 48)
        }
        .accessibilityElement()
        .accessibilityLabel("\(name) печатает")
    }
}

// MARK: - Кнопка «вниз» и ранняя история

/// Круглая кнопка над полем ввода: к последним сообщениям; счётчик — сколько новых пришло, пока читали выше.
struct ScrollToBottomButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
                .background(Circle().fill(Color.appSurface.opacity(0.94)).shadow(color: .black.opacity(0.4), radius: 11, y: 8))
                .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.app(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.brand, in: Capsule())
                            .offset(x: 4, y: -6)
                            .contentTransition(.numericText(value: Double(count)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)
        .accessibilityLabel(count > 0 ? "К последним сообщениям, новых: \(count)" : "К последним сообщениям")
    }
}

/// Пока подгружается более ранняя переписка: капсула со спиннером и два мерцающих пузыря-заглушки.
struct OlderHistoryLoader: View {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Color.brand)
                Text("Загружаем ранние сообщения")
            }
            .font(.app(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.appSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
            if isLoading {
                skeleton(width: 200).frame(maxWidth: .infinity, alignment: .leading)
                skeleton(width: 150).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
        .opacity(isLoading ? 1 : 0.6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private func skeleton(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.appSurface)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.appLine, lineWidth: 1))
            .frame(width: width, height: 38)
            .opacity(dim ? 0.35 : 0.8)
            .accessibilityHidden(true)
    }
}

// MARK: - Жесты пузыря

/// Свайп вправо — ответить: пузырь тянется за пальцем с сопротивлением, слева растёт значок ответа и на 56 pt
/// наливается гранатом с тактильным щелчком. Отпустили за порогом — ответ; пузырь пружиной возвращается.
struct SwipeToReplyModifier: ViewModifier {
    let isEnabled: Bool
    let onReply: () -> Void

    static let threshold: CGFloat = 56
    @State private var offset: CGFloat = 0
    @State private var isHorizontal: Bool?
    @State private var passedThreshold = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) {
                if offset > 0 {
                    let progress = min(offset / Self.threshold, 1)
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(passedThreshold ? Color.white : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(passedThreshold ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.appElevated)))
                        .shadow(color: passedThreshold ? Color.brand.opacity(0.45) : .clear, radius: 7, y: 4)
                        .scaleEffect(0.4 + 0.6 * progress)
                        .opacity(Double(progress))
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
            }
            .simultaneousGesture(isEnabled ? drag : nil)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                if isHorizontal == nil {
                    isHorizontal = value.translation.width > 0 && abs(value.translation.width) > abs(value.translation.height) * 1.6
                }
                guard isHorizontal == true else { return }
                // Сопротивление: чем дальше, тем туже — максимум около 90 pt.
                let width = max(value.translation.width, 0)
                offset = 90 * (1 - exp(-width / 90))
                let passed = offset >= Self.threshold
                if passed != passedThreshold {
                    passedThreshold = passed
                    if passed { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                }
            }
            .onEnded { _ in
                if passedThreshold { onReply() }
                isHorizontal = nil
                passedThreshold = false
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7)) { offset = 0 }
            }
    }
}

extension View {
    func swipeToReply(isEnabled: Bool, onReply: @escaping () -> Void) -> some View {
        modifier(SwipeToReplyModifier(isEnabled: isEnabled, onReply: onReply))
    }
}

/// Сердце над пузырём после двойного касания: вырастает с отскоком (0 → 1,2 → 1), искры разлетаются и гаснут за 0,5 с.
struct HeartBurst: View {
    @State private var phase: CGFloat = 0
    @State private var fade = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sparks: [(angle: Double, color: Color, size: CGFloat)] = [
        (200, .brand, 6), (250, .champagne, 5), (300, .brand, 6), (345, .champagne, 5), (30, .brand, 4), (160, .champagne, 5),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.sparks.enumerated()), id: \.offset) { _, spark in
                Circle()
                    .fill(spark.color)
                    .frame(width: spark.size, height: spark.size)
                    .offset(x: cos(spark.angle * .pi / 180) * 34 * phase, y: sin(spark.angle * .pi / 180) * 34 * phase)
                    .opacity(fade ? 0 : 1)
            }
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.brand)
                .overlay(Image(systemName: "heart").font(.system(size: 40)).foregroundStyle(.white.opacity(0.9)))
                .shadow(color: Color.brand.opacity(0.55), radius: 8, y: 5)
                .scaleEffect(reduceMotion ? 1 : phase)
                .opacity(fade ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                phase = 1
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) { phase = 1 }
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.55)) { fade = true }
        }
    }
}

// MARK: - Ссылки и номера

enum LinkifiedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    /// Ссылки и телефоны в тексте становятся нажимаемыми: в своём пузыре — белые с подчёркиванием, в чужом — шампанским.
    static func attributed(_ text: String, linkColor: Color) -> AttributedString {
        var result = AttributedString(text)
        guard let detector else { return result }
        let nsText = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let swiftRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: result),
                  let url = url(for: match)
            else { continue }
            let range = lower..<upper
            result[range].link = url
            result[range].foregroundColor = linkColor
            result[range].underlineStyle = .single
        }
        return result
    }

    static func url(for match: NSTextCheckingResult) -> URL? {
        if match.resultType == .phoneNumber, let number = match.phoneNumber {
            let digits = number.filter { $0.isNumber || $0 == "+" }
            return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
        }
        guard let url = match.url else { return nil }
        // Только веб и почта: схемы приложений из чужого сообщения не открываем.
        return ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? url : nil
    }
}

// MARK: - Загрузка фото

/// Пузырь фото, которое ещё уходит на сервер: превью с диска, кольцо прогресса с крестиком отмены и «1,8 из 2,9 МБ».
struct PendingPhotoUpload: View {
    let fileURL: URL
    let uploadId: String?
    let onCancel: () -> Void
    @ObservedObject private var center = UploadProgressCenter.shared
    @State private var image: UIImage?

    var body: some View {
        let progress = uploadId.flatMap { center.progress[$0] }
        ZStack {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.appElevated
                }
            }
            .frame(width: 230, height: 250)
            .clipped()
            .overlay(Color.black.opacity(0.35))

            Button(action: onCancel) {
                ZStack {
                    Circle().fill(Color.appBackground.opacity(0.6))
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 3).padding(4)
                    Circle()
                        .trim(from: 0, to: max(progress?.fraction ?? 0, 0.03))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(4)
                        .animation(.linear(duration: 0.2), value: progress?.fraction)
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить загрузку")
            .accessibilityValue(progress.map { "\(Int($0.fraction * 100)) %" } ?? "")
        }
        .overlay(alignment: .bottomLeading) {
            if let progress, progress.total > 0 {
                Text("\(Self.megabytes(progress.sent)) из \(Self.megabytes(progress.total))")
                    .font(.app(size: 11.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appBackground.opacity(0.65), in: Capsule())
                    .padding(10)
            }
        }
        .task(id: fileURL) {
            let url = fileURL
            image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 460, height: 500)) }.value
        }
    }

    static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Новая пара

/// Пустой чат пары (макет «Новая пара — подсказки первой фразы»): два аватара с сердцем, «Вы пара!», общее в анкетах
/// и до трёх фраз для начала — нажатие вставляет фразу в поле, но не отправляет.
struct PairWelcomeView: View {
    let welcome: PairWelcome
    let myAvatarUrl: String?
    let myName: String
    let peerAvatarUrl: String?
    let onPick: (String) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                HStack(spacing: -16) {
                    avatar(myAvatarUrl, name: myName).offset(x: appeared || reduceMotion ? 0 : -24)
                    avatar(peerAvatarUrl, name: welcome.peerName).offset(x: appeared || reduceMotion ? 0 : 24)
                }
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.brandFill))
                    .overlay(Circle().stroke(Color.appBackground, lineWidth: 3))
                    .offset(y: 10)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.2)
            }
            .padding(.bottom, 8)

            Text("Вы пара!")
                .font(.display(size: 22))
            Text(welcome.subtitle)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, -6)

            if !welcome.common.isEmpty {
                ReactionsFlowLayoutCentered(spacing: 6) {
                    ForEach(welcome.common, id: \.self) { name in
                        Text(name)
                            .font(.app(size: 13, weight: .semibold))
                            .foregroundStyle(Color.champagne)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.champagneSoft, in: Capsule())
                    }
                }
                .frame(maxWidth: 320)
            }

            if !welcome.icebreakers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("С чего начать")
                        .font(.app(size: 12.5, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    ForEach(Array(welcome.icebreakers.enumerated()), id: \.offset) { index, phrase in
                        Button { onPick(phrase) } label: {
                            HStack(spacing: 10) {
                                Text(phrase)
                                    .font(.app(size: 14.5))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "pencil.line")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.brand)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 48)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityHint("Вставить в поле сообщения")
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.25 + Double(index) * 0.07), value: appeared)
                    }
                }
                .padding(.top, 24)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { appeared = true }
        }
    }

    private func avatar(_ url: String?, name: String) -> some View {
        AvatarView(avatarUrl: url, name: name, size: 86)
            .overlay(Circle().stroke(Color.appBackground, lineWidth: 3))
    }
}

/// Перенос капсул по строкам с выравниванием по центру — общие интересы в «Вы пара!».
struct ReactionsFlowLayoutCentered: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if widthWithItem > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
