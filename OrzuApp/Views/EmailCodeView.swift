import SwiftUI

/// Второй шаг регистрации: 6-значный код из письма. Одинаков для регистрации по паролю и через Google —
/// отличаются только действия, которые передаёт экран формы.
struct EmailCodeView: View {
    let email: String
    /// false — почту поменять нельзя (она пришла из Google), ссылку «Изменить почту» не показываем.
    let canChangeEmail: Bool
    let resend: () async throws -> Void
    let confirm: (String) async throws -> Void

    /// Как на сервере (RESEND_INTERVAL_MS): чаще одного письма в минуту он не отправит.
    private static let resendInterval: TimeInterval = 60
    private static let codeLength = 6

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var resendAvailableAt = Date().addingTimeInterval(Self.resendInterval)
    @State private var isBusy = false
    /// Код не подошёл: ячейки красные, вместо таймера — «Отправить новый код».
    @State private var isCodeRejected = false
    @State private var message: String?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                envelope
                intro
                codeCells
                if isCodeRejected { rejectedFooter } else { resendFooter }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background(AppBackground())
        .navigationTitle("Подтверждение почты")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                        Text("Назад")
                    }
                }
                .disabled(isBusy)
            }
        }
        .tint(.brand)
        .onAppear { isCodeFocused = true }
    }

    private var envelope: some View {
        Image(systemName: "envelope")
            .font(.system(size: 50, weight: .light))
            .foregroundStyle(Color.brand)
            .frame(width: 132, height: 132)
            .background(Color.brandSoft, in: Circle())
            .background(Circle().fill(Color.brand.opacity(0.08)).padding(-16))
            .background(Circle().fill(Color.brand.opacity(0.04)).padding(-34))
            .padding(.top, 34)
            .padding(.bottom, 20)
            .accessibilityHidden(true)
    }

    private var intro: some View {
        VStack(spacing: 8) {
            Text("Введите код из письма")
                .font(.display(size: 21))
            (Text("Отправили 6 цифр на ") + Text(email).fontWeight(.semibold).foregroundStyle(.primary))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            if canChangeEmail {
                Button("Изменить почту") { dismiss() }
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.brand)
                    .disabled(isBusy)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// Ячейки только рисуют цифры; вводит их одно невидимое поле — так работает и вставка, и подсказка кода из «Почты».
    private var codeCells: some View {
        let digits = Array(code)
        return HStack(spacing: 8) {
            ForEach(0..<Self.codeLength, id: \.self) { index in
                Text(index < digits.count ? String(digits[index]) : "")
                    .font(.display(size: 24, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(cellBorder(at: index), lineWidth: isActiveCell(index) ? 2 : 1)
                    )
            }
        }
        .overlay {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("Код из письма")
                .onChange(of: code) { _, newValue in codeChanged(newValue) }
        }
        .onTapGesture { isCodeFocused = true }
    }

    private func isActiveCell(_ index: Int) -> Bool {
        !isCodeRejected && isCodeFocused && index == min(code.count, Self.codeLength - 1)
    }

    private func cellBorder(at index: Int) -> Color {
        if isCodeRejected { return .red }
        return isActiveCell(index) ? .brand : .appLine
    }

    private var resendFooter: some View {
        VStack(spacing: 4) {
            Text("Код действует 15 минут")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secondsLeft = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
                if secondsLeft > 0 {
                    (Text("Отправить ещё раз через ") + Text(Self.countdown(secondsLeft)).foregroundStyle(.primary))
                        .monospacedDigit()
                } else {
                    Button("Отправить ещё раз") { Task { await sendAgain() } }
                        .foregroundStyle(Color.brand)
                        .fontWeight(.semibold)
                        .disabled(isBusy)
                }
            }
            if let message {
                Text(message).foregroundStyle(.red).padding(.top, 6)
            }
        }
        .font(.app(.subheadline))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var rejectedFooter: some View {
        VStack(spacing: 10) {
            Label(message ?? "Неверный или просроченный код", systemImage: "exclamationmark.circle")
                .font(.app(.subheadline))
                .foregroundStyle(.red)
            Button("Отправить новый код") { Task { await sendAgain() } }
                .font(.app(.callout, weight: .semibold))
                .foregroundStyle(Color.brand)
                .disabled(isBusy)
        }
        .multilineTextAlignment(.center)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            Label("Нет письма? Проверьте «Спам»", systemImage: "envelope.open")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
            Button {
                Task { await submit() }
            } label: {
                if isBusy { ProgressView().tint(.white) } else { Text("Подтвердить") }
            }
            .buttonStyle(.appPrimary)
            .disabled(code.count != Self.codeLength || isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 440)
    }

    private func codeChanged(_ newValue: String) {
        let digits = String(newValue.filter(\.isASCIIDigit).prefix(Self.codeLength))
        if digits != newValue {
            code = digits
            return
        }
        isCodeRejected = false
        message = nil
        // Код целиком (обычно — подсказка из «Почты») отправляем сразу, без лишнего нажатия.
        if digits.count == Self.codeLength { Task { await submit() } }
    }

    private func submit() async {
        guard code.count == Self.codeLength, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await confirm(code)
        } catch let error as APIError where error.isTransient {
            // Связь, а не код: ячейки не красим, код можно отправить ещё раз как есть.
            message = error.localizedDescription
        } catch {
            message = error.localizedDescription
            isCodeRejected = true
        }
    }

    private func sendAgain() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await resend()
            code = ""
            isCodeRejected = false
            message = nil
            resendAvailableAt = Date().addingTimeInterval(Self.resendInterval)
            isCodeFocused = true
        } catch {
            message = error.localizedDescription
        }
    }

    /// 42 → «0:42».
    private static func countdown(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
