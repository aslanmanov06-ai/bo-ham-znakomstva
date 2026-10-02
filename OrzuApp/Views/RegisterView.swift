import AuthenticationServices
import SwiftUI

/// Регистрация по паролю: форма → код из письма (EmailCodeView) → аккаунт. Дальше корневой экран покажет анкету.
/// Сверху — «Продолжить с Apple»: так быстрее всего, без пароля и кода.
struct RegisterView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var appStatus = AppStatus.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var appleNonce = ""

    var body: some View {
        NavigationStack {
            if appStatus.registrationClosed {
                RegistrationClosedView { dismiss() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        RegistrationSteps(current: 1)
                            .padding(.top, 6)

                        appleButton

                        LabeledAppField(title: String(localized: "Имя")) {
                            TextField("Как к вам обращаться", text: $displayName)
                                .textContentType(.givenName)
                        }
                        LabeledAppField(
                            title: String(localized: "Логин"),
                            hint: String(localized: "Латиница, цифры и «_». По логину вас можно найти и войти в приложение."),
                            error: usernameError
                        ) {
                            TextField("например, madina_k", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                // Сервер хранит логин строчными — показываем сразу так, как он сохранится.
                                .onChange(of: username) {
                                    usernameError = nil
                                    username = username.lowercased()
                                }
                        }
                        LabeledAppField(
                            title: String(localized: "Почта"),
                            hint: String(localized: "Придёт код подтверждения. Никому не показывается."),
                            error: emailError
                        ) {
                            TextField("name@mail.ru", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: email) { emailError = nil }
                        }
                        LabeledAppField(
                            title: String(localized: "Телефон"),
                            hint: String(localized: "Защищает от фейков и повторной регистрации нарушителей. Никому не показывается, SMS не отправляем.")
                        ) {
                            TextField("+992 90 123 45 67", text: $phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                        }
                        LabeledAppField(title: String(localized: "Пароль")) {
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
        }
        .tint(.brand)
        .interactiveDismissDisabled(isBusy)
    }

    /// Новый человек через Apple попадает в анкету GoogleRegistrationView, которую показывает экран входа,
    /// поэтому регистрацию сначала закрываем — два листа сразу SwiftUI не покажет.
    private var appleButton: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                appleNonce = LoginView.makeNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = LoginView.sha256(appleNonce)
            } onCompletion: { result in
                let nonce = appleNonce
                dismiss()
                Task { await authViewModel.signInWithApple(result, nonce: nonce) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: AppMetrics.buttonHeight)
            .clipShape(Capsule())
            .disabled(isBusy)

            Text("Быстрее всего — без пароля")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Rectangle().fill(Color.appLine).frame(height: 1)
                Text("или по почте")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(Color.appLine).frame(height: 1)
            }
            .padding(.top, 2)
        }
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
        } catch let error as APIError where error.code == ServerErrorCode.registrationClosed {
            // Регистрацию закрыли, пока человек заполнял форму: вместо формы — объяснение.
            AppStatus.shared.markRegistrationClosed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Где человек на пути регистрации: аккаунт → код из письма → анкета → фото.
struct RegistrationSteps: View {
    let current: Int

    private static let total = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...Self.total, id: \.self) { step in
                    Capsule()
                        .fill(step <= current ? Color.brand : Color.appLine)
                        .frame(height: 4)
                }
            }
            Text("Шаг \(current) из \(Self.total) · аккаунт → код из письма → анкета → фото")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
