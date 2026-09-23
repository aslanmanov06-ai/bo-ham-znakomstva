import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Создайте аккаунт")
                            .font(.display(.title))
                        Text("Дальше — короткая анкета: пол, дата рождения, город и одно фото.")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        AppField(systemImage: "at") {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        AppField(systemImage: "person") {
                            TextField("Имя", text: $displayName)
                                .textContentType(.givenName)
                        }
                        AppField(systemImage: "lock") {
                            SecureField("Пароль (мин. 8 символов)", text: $password)
                                .textContentType(.newPassword)
                        }
                    }

                    if let errorMessage = authViewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.app(.footnote))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            await authViewModel.register(username: username, displayName: displayName, password: password)
                            if authViewModel.isAuthenticated { dismiss() }
                        }
                    } label: {
                        if authViewModel.isLoading { ProgressView().tint(.white) } else { Text("Продолжить") }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(username.count < 3 || displayName.isEmpty || password.count < 8 || authViewModel.isLoading)
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
