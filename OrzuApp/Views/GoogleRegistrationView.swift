import SwiftUI

/// Анкета после первого входа через Google: аккаунта ещё нет — выбрать username и имя, подтвердить почту кодом.
/// Код уходит на почту из Google; свою почту человек вводит, только если Google её не передал.
struct GoogleRegistrationView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let registration: GoogleRegistration

    @State private var username: String
    @State private var displayName: String
    @State private var typedEmail = ""
    @State private var phone = PhoneRules.defaultPrefix
    @State private var isBusy = false
    @State private var usernameError: String?
    @State private var emailError: String?
    @State private var errorMessage: String?
    @State private var showCode = false

    init(registration: GoogleRegistration) {
        self.registration = registration
        _username = State(initialValue: registration.suggestedUsername)
        _displayName = State(initialValue: registration.profile.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Почти готово")
                            .font(.display(size: 22))
                        Text("Подтвердите почту из Google — пришлём на неё код. Это защищает аккаунт от чужих входов.")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                    if let googleEmail = registration.profile.email {
                        googleEmailCard(googleEmail)
                    } else {
                        LabeledAppField(title: "Почта", hint: "Google не передал почту — укажите её, на неё придёт код.", error: emailError) {
                            TextField("name@mail.ru", text: $typedEmail)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: typedEmail) { emailError = nil }
                        }
                    }

                    LabeledAppField(title: "Username", hint: "По нему вас найдут в поиске.", error: usernameError) {
                        TextField("латиница, цифры и «_»", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            // Сервер хранит username строчными — показываем сразу так, как он сохранится.
                            .onChange(of: username) {
                                usernameError = nil
                                username = username.lowercased()
                            }
                    }
                    LabeledAppField(title: "Имя") {
                        TextField("Как к вам обращаться", text: $displayName)
                            .textContentType(.givenName)
                    }
                    LabeledAppField(title: "Телефон", hint: "Обязательно. Никому не показывается.") {
                        TextField("+992 90 123 45 67", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }

                    Text("Пароль можно задать позже в настройках.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

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
            .navigationTitle("Завершите регистрацию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { authViewModel.pendingGoogleRegistration = nil }
                }
            }
            .navigationDestination(isPresented: $showCode) {
                EmailCodeView(
                    email: codeEmail,
                    canChangeEmail: registration.profile.email == nil,
                    resend: { try await authViewModel.requestGoogleRegistrationCode(registration, username: username, email: typedEmailIfNeeded) },
                    confirm: { code in
                        try await authViewModel.completeGoogleRegistration(
                            registration, username: username, displayName: displayName, email: typedEmailIfNeeded,
                            phone: PhoneRules.normalized(phone), code: code
                        )
                    }
                )
            }
        }
        .tint(.brand)
        .interactiveDismissDisabled(isBusy)
    }

    private func googleEmailCard(_ email: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.champagne)
                .frame(width: 38, height: 38)
                .background(Color.champagneSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Почта из Google")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(email)
                    .font(.app(.callout, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Изменить нельзя")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .appCard(cornerRadius: 20, padding: nil)
        .accessibilityElement(children: .combine)
    }

    /// Своя почта уходит на сервер, только если Google её не передал.
    private var typedEmailIfNeeded: String? {
        registration.profile.email == nil ? typedEmail.trimmingCharacters(in: .whitespaces).lowercased() : nil
    }

    private var codeEmail: String {
        registration.profile.email ?? typedEmailIfNeeded ?? ""
    }

    private var isValid: Bool {
        UsernameRules.isValid(username)
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && codeEmail.contains("@")
            && PhoneRules.isValid(phone)
    }

    private func requestCode() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await authViewModel.requestGoogleRegistrationCode(registration, username: username, email: typedEmailIfNeeded)
            showCode = true
        } catch let error as APIError where error.code == ServerErrorCode.codeAlreadySent {
            // Вернулись с экрана кода: прежний код на эту почту ещё действует.
            showCode = true
        } catch let error as APIError where error.code == ServerErrorCode.emailTaken {
            if registration.profile.email == nil { emailError = error.localizedDescription } else { errorMessage = error.localizedDescription }
        } catch let error as APIError where error.code == ServerErrorCode.usernameTaken {
            usernameError = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
