import SwiftUI

/// Высота поля ввода и диаметр круглых кнопок рядом с ним — по минимальной зоне касания HIG.
enum GlassMetrics {
    static let controlSize: CGFloat = 44
}

/// Плавающая стеклянная строка ввода внизу чата: [дополнительная кнопка] [поле] [отправить] [кнопки справа].
struct ComposerBar<Accessory: View, Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    let canSend: Bool
    /// «arrow.up» — отправить, «checkmark» — сохранить правку.
    var sendSystemImage = "arrow.up"
    /// false — вместо кнопки отправки только trailing (в чате: микрофон и «кружок», пока поле пустое).
    var showsSendButton = true
    let onSend: () -> Void
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                accessory

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: GlassMetrics.controlSize)
                    .glassSurface(in: RoundedRectangle(cornerRadius: GlassMetrics.controlSize / 2, style: .continuous))

                if showsSendButton {
                    Button(action: onSend) {
                        Image(systemName: sendSystemImage)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .frame(width: GlassMetrics.controlSize, height: GlassMetrics.controlSize)
                            .background {
                                // Готово к отправке — сплошной гранат, как главные кнопки; пустое поле — тихое стекло.
                                if canSend {
                                    Circle().fill(.brandFill)
                                } else {
                                    Color.clear.glassSurface(in: Circle())
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Отправить")
                    .animation(.snappy, value: canSend)
                }

                trailing
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

extension ComposerBar where Accessory == EmptyView, Trailing == EmptyView {
    init(text: Binding<String>, placeholder: String, canSend: Bool, onSend: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, canSend: canSend, onSend: onSend) { EmptyView() } trailing: { EmptyView() }
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
