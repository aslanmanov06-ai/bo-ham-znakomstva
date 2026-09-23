import SwiftUI

/// Анкета после первого входа через Google: аккаунта в OrzuApp ещё нет, нужно выбрать username и имя.
struct GoogleRegistrationView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let registration: GoogleRegistration

    @State private var username: String
    @State private var displayName: String

    init(registration: GoogleRegistration) {
        self.registration = registration
        _username = State(initialValue: registration.suggestedUsername)
        _displayName = State(initialValue: registration.profile.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Имя", text: $displayName)
                } header: {
                    Text("Данные аккаунта")
                } footer: {
                    Text("Username — латиница, цифры и «_», от 3 символов. По нему вас найдут в поиске.")
                }

                if let email = registration.profile.email {
                    Section {
                        Text(email)
                    } header: {
                        Text("Почта из Google")
                    } footer: {
                        Text("Станет резервной почтой: по ней можно входить и восстанавливать пароль. Пароль можно задать позже в настройках.")
                    }
                }

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .appScreenBackground()
            .navigationTitle("Завершите регистрацию")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(authViewModel.isLoading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { authViewModel.pendingGoogleRegistration = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task { await authViewModel.completeGoogleRegistration(username: username, displayName: displayName) }
                    }
                    .disabled(!isValid || authViewModel.isLoading)
                }
            }
        }
    }

    private var isValid: Bool {
        UsernameRules.isValid(username) && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
