import SwiftUI

/// Высота поля ввода и диаметр круглых кнопок рядом с ним — по минимальной зоне касания HIG.
enum GlassMetrics {
    static let controlSize: CGFloat = 44
    /// Видимый круг кнопок внутри капсулы поля; зона касания остаётся controlSize.
    static let inlineIconSize: CGFloat = 36
}

/// Что делает круглая кнопка справа, пока отправлять нечего (в чате — запись голосового).
struct ComposerIdleAction {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void
}

/// Строка ввода внизу чата по макету «Отправка сообщений»: одна капсула — [цитата] / [accessory] [поле] [inlineTrailing],
/// справа круглая кнопка, которая превращается из idleAction (микрофона) в «Отправить».
struct ComposerBar<Header: View, Accessory: View, InlineTrailing: View>: View {
    @Binding var text: String
    let placeholder: String
    let canSend: Bool
    /// «arrow.up» — отправить, «checkmark» — сохранить правку.
    var sendSystemImage = "arrow.up"
    /// nil — кнопка всегда «Отправить» (неактивна, пока нечего отправлять).
    var idleAction: ComposerIdleAction?
    /// true — кнопка сейчас выполняет idleAction (в чате: поле пустое). Иконка idleAction остаётся в дереве, чтобы красиво уходить и возвращаться.
    var isIdle = false
    let onSend: () -> Void
    /// Цитата ответа или правки — внутри капсулы над полем.
    @ViewBuilder var header: Header
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var inlineTrailing: InlineTrailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sendCount = 0

    private var showsIdleAction: Bool { idleAction != nil && isIdle }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(spacing: 0) {
                header
                HStack(alignment: .bottom, spacing: 0) {
                    accessory

                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .tint(Color.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(minHeight: GlassMetrics.controlSize)

                    inlineTrailing
                }
            }
            .glassSurface(in: RoundedRectangle(cornerRadius: GlassMetrics.controlSize / 2, style: .continuous))

            actionButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        // Одна пружина на всё: кнопка-оборотень, складывание «кружка», появление цитаты, рост поля.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7), value: showsIdleAction)
        .animation(.snappy, value: canSend)
        .sensoryFeedback(.selection, trigger: showsIdleAction) { _, idle in !idle }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount)
    }

    /// Одна кнопка на два состояния: иконки меняются поворотом и масштабом, фон — из стекла в гранат.
    private var actionButton: some View {
        Button {
            if showsIdleAction, let idleAction {
                idleAction.action()
            } else {
                sendCount += 1
                onSend()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.brandFill)
                    .shadow(color: Color.brand.opacity(0.38), radius: 9, y: 6)
                    .opacity(isSendReady ? 1 : 0)
                    .scaleEffect(isSendReady || reduceMotion ? 1 : 0.6)

                if let idleAction {
                    morphingIcon(idleAction.systemImage, isShown: showsIdleAction, color: .primary)
                }
                morphingIcon(sendSystemImage, isShown: !showsIdleAction, color: canSend ? .white : .secondary)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
            .background {
                if !isSendReady {
                    Color.clear.glassSurface(in: Circle())
                }
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!showsIdleAction && !canSend)
        .accessibilityLabel(showsIdleAction ? idleAction?.accessibilityLabel ?? "Отправить" : "Отправить")
    }

    private var isSendReady: Bool { !showsIdleAction && canSend }

    /// Уходящая иконка поворачивается на четверть оборота и сжимается, приходящая — наоборот.
    private func morphingIcon(_ systemImage: String, isShown: Bool, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.app(.body, weight: .semibold))
            .foregroundStyle(color)
            .opacity(isShown ? 1 : 0)
            .rotationEffect(.degrees(isShown || reduceMotion ? 0 : -90))
            .scaleEffect(isShown || reduceMotion ? 1 : 0.5)
    }
}

extension ComposerBar where Header == EmptyView, Accessory == EmptyView, InlineTrailing == EmptyView {
    init(text: Binding<String>, placeholder: String, canSend: Bool, onSend: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, canSend: canSend, onSend: onSend) {
            EmptyView()
        } accessory: {
            EmptyView()
        } inlineTrailing: {
            EmptyView()
        }
    }
}

/// Кнопка внутри капсулы поля: видимый круг 36 pt, зона касания 44 pt. `filled` — на приподнятой подложке, как «+».
struct ComposerInlineIcon: View {
    let systemImage: String
    var filled = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.app(filled ? .callout : .title3, weight: filled ? .bold : .regular))
            .foregroundStyle(filled ? Color.primary : Color.secondary)
            .frame(width: GlassMetrics.inlineIconSize, height: GlassMetrics.inlineIconSize)
            .background { if filled { Circle().fill(Color.appElevated) } }
            .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
            .contentShape(Rectangle())
    }
}

/// Цитата над полем: на что отвечаем или что правим. Гранатовая черта, заголовок, превью и крестик.
struct ComposerQuote: View {
    let title: String
    let text: String
    let cancelLabel: LocalizedStringKey
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.brand)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(.caption, weight: .bold)).foregroundStyle(Color.brand)
                Text(text).font(.app(.footnote)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.app(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cancelLabel)
        }
        .padding(.leading, 10)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding([.horizontal, .top], 3)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Нажатая кнопка сжимается до 88 % и пружинит обратно.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Круглая стеклянная кнопка-иконка того же размера, что и кнопка отправки.
struct GlassIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.app(.body, weight: .semibold))
            .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
            .glassSurface(in: Circle(), interactive: true)
    }
}

/// Гранатовая круглая кнопка со свечением — «Отправить» там, где она не превращается из микрофона (запись голосового).
struct BrandCircleIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
            .background {
                Circle()
                    .fill(.brandFill)
                    .shadow(color: Color.brand.opacity(0.38), radius: 9, y: 6)
            }
    }
}
