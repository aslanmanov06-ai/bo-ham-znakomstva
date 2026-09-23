import SwiftUI

/// Восстановление пароля по подтверждённой резервной почте: код из письма + новый пароль.
struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var codeSent = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Резервная почта", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(codeSent ? "Отправить код ещё раз" : "Отправить код") { Task { await requestCode() } }
                        .disabled(!email.contains("@") || isBusy)
                } footer: {
                    Text("Код придёт, только если эта почта подтверждена в настройках аккаунта.")
                }

                if codeSent {
                    Section {
                        TextField("Код из письма", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        SecureField("Новый пароль (мин. 8 символов)", text: $newPassword)
                        Button("Сменить пароль") { Task { await confirm() } }
                            .disabled(code.count != 6 || newPassword.count < 8 || isBusy)
                    }
                }

                if let message {
                    Text(message).foregroundStyle(isError ? .red : .secondary)
                }
            }
            .appScreenBackground()
            .navigationTitle("Восстановление пароля")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func requestCode() async {
        await run {
            try await APIClient.shared.requestPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
            codeSent = true
            message = "Если почта привязана к аккаунту, письмо с кодом уже в пути."
        }
    }

    private func confirm() async {
        await run {
            try await APIClient.shared.confirmPasswordReset(email: email.trimmingCharacters(in: .whitespaces), code: code, newPassword: newPassword)
            message = "Пароль изменён — войдите с новым паролем."
            codeSent = false
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}
