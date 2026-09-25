import SwiftUI

/// Регистрация по паролю: форма → код из письма (EmailCodeView) → аккаунт. Дальше корневой экран покажет анкету.
struct RegisterView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var phone = PhoneRules.defaultPrefix
    @State private var password = ""
    @State private var isBusy = false
    @State private var usernameError: String?
    @State private var emailError: String?
    @State private var errorMessage: String?
    @State private var showCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Создайте аккаунт")
                            .font(.display(size: 22))
                        Text("На почту придёт код подтверждения. Дальше — короткая анкета: пол, дата рождения, город и одно фото.")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                    LabeledAppField(title: "Username", error: usernameError) {
                        TextField("латиница, цифры и «_»", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { usernameError = nil }
                    }
                    LabeledAppField(title: "Имя") {
                        TextField("Как к вам обращаться", text: $displayName)
                            .textContentType(.givenName)
                    }
                    LabeledAppField(
                        title: "Почта",
                        hint: "Для входа и восстановления пароля. Никому не показывается.",
                        error: emailError
                    ) {
                        TextField("name@mail.ru", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: email) { emailError = nil }
                    }
                    LabeledAppField(title: "Телефон", hint: "Обязательно. Никому не показывается.") {
                        TextField("+992 90 123 45 67", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }
                    LabeledAppField(title: "Пароль") {
                        SecureField("Не меньше 8 символов", text: $password)
                            .textContentType(.newPassword)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.app(.footnote))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await requestCode() }
                } label: {
                    if isBusy { ProgressView().tint(.white) } else { Text("Получить код") }
                }
                .buttonStyle(.appPrimary)
                .disabled(!isValid || isBusy)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: 440)
            }
            .background(AppBackground())
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showCode) {
                EmailCodeView(
                    email: normalizedEmail,
                    canChangeEmail: true,
                    resend: { try await authViewModel.requestRegistrationCode(email: normalizedEmail, username: username) },
                    confirm: { code in
                        try await authViewModel.register(
                            username: username, displayName: displayName, password: password, email: normalizedEmail,
                            phone: PhoneRules.normalized(phone), code: code
                        )
                        dismiss()
                    }
                )
            }
        }
        .tint(.brand)
        .interactiveDismissDisabled(isBusy)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var isValid: Bool {
        UsernameRules.isValid(username)
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && normalizedEmail.contains("@")
            && PhoneRules.isValid(phone)
            && password.count >= 8
    }

    private func requestCode() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await authViewModel.requestRegistrationCode(email: normalizedEmail, username: username)
            showCode = true
        } catch let error as APIError where error.code == ServerErrorCode.codeAlreadySent {
            // Вернулись с экрана кода, ничего не изменив: прежний код на эту почту ещё действует.
            showCode = true
        } catch let error as APIError where error.code == ServerErrorCode.emailTaken {
            emailError = error.localizedDescription
        } catch let error as APIError where error.code == ServerErrorCode.usernameTaken {
            usernameError = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
